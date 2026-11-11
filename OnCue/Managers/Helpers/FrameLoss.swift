//
//  FrameLoss.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/20/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import Foundation

/// Frames can disappear from a recording in several places, and every one of them used to fail
/// quietly (spec 0024). For a security camera that's the worst kind of failure: the file exists,
/// it plays, and what it doesn't show is the thing you were watching for.
///
/// Two measurements, answering different questions. `Tally` says *where* frames went, which is for
/// working out why. `Gaps` is measured from the frames that actually landed, so it catches every
/// drop site at once and anything nobody thought of; that's what decides whether the file's name
/// says something.
enum FrameLoss {
  /// Where a frame was lost.
  enum Reason: String, CaseIterable {
    /// The encoder was already behind, so the pipeline shed this frame rather than let it hold a
    /// capture buffer. Deliberate, and still worth counting.
    case encoderBehind
    /// The compressor returned an error or no data.
    case encodeFailed
    /// `AVAssetWriterInput.append` refused the sample.
    case writerRefused
    /// macOS itself dropped the frame before OnCue saw it.
    case captureDropped
  }

  /// How many frames were lost, by reason.
  struct Tally: Equatable {
    private(set) var counts: [Reason: Int] = [:]

    mutating func record(_ reason: Reason) {
      counts[reason, default: 0] += 1
    }

    var total: Int { counts.values.reduce(0, +) }

    /// For logging: "encoderBehind 12, writerRefused 3", empty when nothing was lost.
    var summary: String {
      Reason.allCases.compactMap { reason in
        guard let count = counts[reason], count > 0 else { return nil }
        return "\(reason.rawValue) \(count)"
      }.joined(separator: ", ")
    }
  }

  /// What the frames that landed say about the ones that didn't. Accumulated as they're written,
  /// so a long recording costs three numbers rather than a list of timestamps.
  struct Gaps: Equatable {
    private(set) var written = 0
    private(set) var missing: Double = 0
    private(set) var longest: Double = 0
    private var lastTime: Double?

    /// A frame written at `time`, nominally `interval` seconds long. A step bigger than one and a
    /// half intervals is a gap; the half is slack for ordinary jitter.
    mutating func wrote(at time: Double, interval: Double) {
      written += 1
      defer { lastTime = time }
      guard let last = lastTime, interval > 0 else { return }
      let step = time - last
      guard step > interval * 1.5 else { return }
      let lost = step - interval
      missing += lost
      longest = max(longest, lost)
    }

    /// How many frames the recording should have held, from what it covered and how long a frame
    /// lasts. Zero when nothing is known yet.
    func expected(interval: Double) -> Int {
      guard interval > 0, written > 0 else { return 0 }
      return written + Int((missing / interval).rounded())
    }
  }

  /// A gap this long means blindness rather than a stutter: long enough for someone to cross the
  /// frame unseen, and well clear of the jitter healthy recordings show.
  static let longestGapWorthSaying = 1.0
  /// Losing more than this share catches shedding that's spread too evenly to leave a gap.
  static let shareWorthSaying = 0.1

  /// Whether the loss is worth putting in the file's name. Two tests because they catch different
  /// failures: a long hole, or a lot of frames missing without one.
  static func worthSaying(longest: Double, missing: Double, written: Int, expected: Int) -> Bool {
    guard written > 0, expected > 0 else { return false }
    if longest >= longestGapWorthSaying {
      return true
    }
    return Double(expected - written) / Double(expected) > shareWorthSaying
  }

  /// What the name says, rounded to a whole second, or nil when there's nothing to say. Total time
  /// rather than a percentage: it says how much can't be seen without arithmetic.
  /// The longest suffix `nameSuffix` can produce, for whoever has to leave room for it in a file
  /// name. Seven digits of seconds is over a hundred days of missing footage, so the real one is
  /// always shorter.
  static let longestNameSuffix = " - 9999999s missing"

  static func nameSuffix(longest: Double, missing: Double, written: Int, expected: Int) -> String? {
    guard worthSaying(longest: longest, missing: missing, written: written, expected: expected) else {
      return nil
    }
    let seconds = max(1, Int(missing.rounded()))
    return " - \(seconds)s missing"
  }
}
