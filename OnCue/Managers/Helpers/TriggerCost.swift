//
//  TriggerCost.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/21/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import Foundation

/// What the trigger has been producing lately (spec 0033).
///
/// A recordings folder fills because of how often OnCue records, not how big each recording is,
/// and until now nothing said so. The control is already there, a slider with a live meter, but
/// there was no way to find out what a setting produced once you walked away short of opening the
/// folder and counting.
///
/// This reports and does not conclude. It says how many recordings there were and how long they
/// typically ran, next to the shortest one OnCue can make, and leaves the reader to supply the
/// thing OnCue doesn't have, which is whether an eleven second event at their door is a delivery
/// or a branch.
enum TriggerCost {
  /// What the encoder is held to, whatever the picture. It lives here rather than beside the
  /// compression session because this is the code that depends on it being fixed: reading a
  /// recording's length back out of its size only works while every recording costs the same per
  /// second. `CameraPipeline` sets the encoder from it.
  static let assumedBitsPerSecond = 8_000_000.0

  /// The stretch reported on. Always the same length, so it means the same thing every time it's
  /// read, and it survives disarming, which is when someone usually looks.
  static let window: TimeInterval = 24 * 60 * 60

  /// Below this there isn't enough to describe. A typical worked out from three recordings is
  /// noise wearing a number's clothes.
  ///
  /// This is a floor on whether the statement would be true, never on whether it flatters the
  /// setting. A quiet day saying nothing is not OnCue approving of anything.
  static let enoughToDescribe = 10

  struct Summary: Equatable {
    let count: Int
    /// The middle recording's length, in seconds. A median rather than a mean, because one long
    /// event would drag a mean away from what the folder is actually full of.
    let typicalSeconds: Double
    /// The shortest recording OnCue can make with these settings, for the reader to compare
    /// against. Not a judgement, just the other end of the ruler.
    let shortestPossibleSeconds: Double

    /// The popover's line. When the typical recording is close to the shortest possible one,
    /// it says so outright, since that's the fact the two numbers were there to let the reader
    /// find (spec 0033, reworded 2026-09-23); otherwise it gives both numbers and the floor.
    var text: String {
      let typical = Int(typicalSeconds.rounded())
      let shortest = Int(shortestPossibleSeconds.rounded())
      if typicalSeconds < shortestPossibleSeconds * Summary.barelyLongerFactor {
        return String(localized: "\(count) recordings in the last day, most barely longer than the \(shortest)s minimum.",
                      comment: "Popover; never fewer than three recordings, so no singular; the second argument is seconds")
      }
      return String(localized: "\(count) recordings in the last day, typically \(typical)s. OnCue can't make one shorter than \(shortest)s.",
                    comment: "Popover; never fewer than three recordings, so no singular; the other arguments are seconds")
    }

    /// Under one and a half times the floor, a typical recording captured only a moment.
    static let barelyLongerFactor = 1.5
  }

  /// The shortest recording these settings can produce: the pre-roll it reaches back for, plus the
  /// wait after movement stops. Both are the user's own numbers.
  static func shortestPossibleSeconds(preRoll: Double, timeout: Int) -> Double {
    return max(0, preRoll) + Double(max(0, timeout))
  }

  /// Seconds of footage in a recording of `bytes`. The encoder holds a fixed bitrate whatever the
  /// picture, so size is a good enough proxy for duration and it's already known without opening
  /// anything.
  static func seconds(bytes: Int64, bitsPerSecond: Double) -> Double {
    guard bitsPerSecond > 0 else { return 0 }
    return Double(bytes) * 8 / bitsPerSecond
  }

  /// What to say, or nil when there isn't enough in the window to say anything true.
  static func summary(recordings: [DiskBudget.Recording], now: Date, bitsPerSecond: Double,
                      preRoll: Double, timeout: Int) -> Summary? {
    // Movies only: the still beside each recording (spec 0053) is OnCue's own file by name, and
    // counting it would double the count and halve the typical length.
    let movies = recordings.filter { $0.url.pathExtension.lowercased() == "mov" }
    let recent = movies.filter { now.timeIntervalSince($0.started) <= window && $0.started <= now }
    guard recent.count >= enoughToDescribe else { return nil }

    let lengths = recent.map { seconds(bytes: $0.bytes, bitsPerSecond: bitsPerSecond) }.sorted()
    let middle = lengths[lengths.count / 2]
    return Summary(count: recent.count,
                   typicalSeconds: middle,
                   shortestPossibleSeconds: shortestPossibleSeconds(preRoll: preRoll, timeout: timeout))
  }
}
