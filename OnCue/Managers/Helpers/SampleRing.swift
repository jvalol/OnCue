//
//  SampleRing.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/19/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import Foundation

/// The last few seconds of samples, oldest first, for pre-roll (spec 0013). Times are seconds on the
/// capture clock. Video can only start at a keyframe, so trimming keeps the latest keyframe at or
/// before the window's start, and a recording's footage starts at a keyframe too. Audio samples are
/// all keyframes.
struct SampleRing<Payload> {
  struct Entry {
    let time: Double
    let isKeyframe: Bool
    let payload: Payload
  }

  /// A hard ceiling, for a device whose timestamps never advance. Nothing else here can bound the
  /// ring in that case, since every sample looks like it arrived at the same moment. At 30 seconds
  /// of 60fps video this is more than ten times what the window ever needs, so it only bites when
  /// the timestamps are already nonsense.
  static var maximumEntries: Int { 20_000 }

  private(set) var entries: [Entry] = []

  mutating func append(_ entry: Entry) {
    entries.append(entry)
    if entries.count > SampleRing.maximumEntries {
      entries.removeFirst(entries.count - SampleRing.maximumEntries)
    }
  }

  mutating func removeAll() {
    entries.removeAll()
  }

  /// The newest sample's time, in the device's own timebase. Nil when nothing is buffered.
  var newest: Double? {
    return entries.last?.time
  }

  /// The window measured back from the newest sample: what counts as too old to keep.
  ///
  /// Against the ring's own times rather than a clock outside it. Capture devices timestamp in
  /// their own timebase, and a virtual camera or an external webcam can sit well ahead of or
  /// behind the host clock. Comparing the two meant nothing was ever old enough to drop and the
  /// ring grew until the app was killed, which on an unattended camera is a silent, permanent stop.
  func cutoff(window: Double) -> Double? {
    return entries.last.map { $0.time - window }
  }

  /// Drops what's older than `window` seconds before the newest sample, keeping the keyframe that
  /// decodes it.
  mutating func trim(window: Double) {
    guard let cutoff = cutoff(window: window),
      let keep = entries.lastIndex(where: { $0.isKeyframe && $0.time <= cutoff }) else {
      return
    }
    entries.removeFirst(keep)
  }

  /// Where a recording's footage should start: the latest keyframe at or before `cutoff`, or the
  /// earliest one after it if none is that old. Only keyframes after `lastWritten` count, so a
  /// recording restarted after an interruption doesn't repeat footage already in the last file.
  func startTime(notAfter cutoff: Double, after lastWritten: Double?) -> Double? {
    let candidates = entries.filter { $0.isKeyframe && $0.time > (lastWritten ?? -.infinity) }
    return candidates.last(where: { $0.time <= cutoff })?.time ?? candidates.first?.time
  }

  func entries(from start: Double) -> [Entry] {
    return entries.filter { $0.time >= start }
  }
}

enum PreRoll {
  static let maximumSeconds = 30.0

  /// The pre-roll setting, held to 0 through 30 seconds.
  static func clamp(_ seconds: Double) -> Double {
    return min(max(seconds, 0), maximumSeconds)
  }

  static func seconds(defaults: UserDefaults = .standard) -> Double {
    return clamp(defaults.double(forKey: "preRollSeconds"))
  }

  /// The wall-clock time a sample was captured, for naming a file after when its footage begins.
  ///
  /// Both times are the device's own, and only the gap between them is used, which is what makes
  /// this immune to a device whose timebase disagrees with the host clock. Reading the host clock
  /// here instead named recordings from a device an hour ahead an hour into the future, and spec
  /// 0029's rolling window sorts on that name: a future-dated recording never sorts as the oldest,
  /// so it was never deleted and the window quietly failed to free anything.
  static func date(ofSampleTime time: Double, newestSampleTime: Double, now: Date) -> Date {
    return now.addingTimeInterval(time - newestSampleTime)
  }
}
