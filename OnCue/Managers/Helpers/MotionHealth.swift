//
//  MotionHealth.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/21/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import Foundation

/// Whether motion is actually being measured (spec 0030).
///
/// Detection can stop while everything around it looks fine. The camera is on and lit, the preview
/// still shows a picture, the meter holds whatever it last showed, and nothing ever records. The
/// only evidence is that measurements stopped arriving, so that is what this watches.
enum MotionHealth {
  /// How long without a measurement before OnCue says anything.
  ///
  /// Long enough to clear stalls that aren't failures: a texture cache that fails to allocate
  /// recovers on the next frame, and capture warm-up measures 856ms cold, so a camera switch can
  /// go most of a second with nothing measured while working perfectly. Short enough that someone
  /// who has just armed it is still standing there, which is the only moment anyone is likely to
  /// see this while it still matters. It is also the Arm countdown, the app's human unit.
  static let stoppedAfter: TimeInterval = 5

  /// Whether detection counts as stopped.
  ///
  /// This keys on measurements arriving, never on what they say. A camera pointed at a wall is
  /// measuring perfectly well and reporting a level of zero, so it is never stopped. A camera
  /// OnCue released on purpose (spec 0023) isn't measuring and isn't meant to be, which is what
  /// `capturing` is for. `lastMeasured` is nil before the first measurement of a session, when
  /// there is nothing yet to be late.
  static func stopped(capturing: Bool, lastMeasured: Date?, now: Date) -> Bool {
    guard capturing, let last = lastMeasured else { return false }
    return now.timeIntervalSince(last) >= stoppedAfter
  }

  /// The gap a finished outage leaves behind: from the last measurement before it to the moment
  /// measuring resumed. Nil when nothing was missed, so a recovery within the window says nothing.
  ///
  /// This is the same news the popover already gives after the Mac sleeps while armed, which is
  /// that there is a stretch with no footage in it (spec 0027's notice line, via `wasNotWatching`).
  static func outage(from lastMeasured: Date?, to resumedAt: Date) -> (from: Date, to: Date)? {
    guard let last = lastMeasured, resumedAt.timeIntervalSince(last) >= stoppedAfter else {
      return nil
    }
    return (from: last, to: resumedAt)
  }
}
