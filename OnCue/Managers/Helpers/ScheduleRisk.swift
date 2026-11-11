//
//  ScheduleRisk.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/23/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import Foundation

/// A schedule only runs while OnCue is open, and arming at login only happens if something
/// opens OnCue, so after a restart neither does anything unless OnCue opens at login (specs 0051
/// and 0060). This names the mismatch; nothing changes the login item on the user's behalf, ever.
enum ScheduleRisk {
  /// True when a schedule with something coming, or arming at login, is on and macOS won't open
  /// OnCue at login: off, or switched off in System Settings and awaiting approval.
  static func cannotSurviveRestart(scheduleEnabled: Bool, hasWindows: Bool, armAtLogin: Bool = false,
                                   loginState: LoginItem.State) -> Bool {
    return ((scheduleEnabled && hasWindows) || armAtLogin) && loginState != .on
  }

  /// The rule from the app's own state, either reason, for the popover.
  static func current(defaults: UserDefaults = .standard, loginState: LoginItem.State = LoginItem.app.state, now: Date = Date()) -> Bool {
    return cannotSurviveRestart(scheduleEnabled: Schedule.isEnabled(in: defaults),
                                hasWindows: Schedule.load(from: defaults).nextStart(after: now) != nil,
                                armAtLogin: defaults.bool(forKey: "armAtLogin"),
                                loginState: loginState)
  }

  /// The schedule's reason alone, for the note under the schedule in Settings, which talks about
  /// the schedule and shouldn't turn orange for the arm box two sections up (0060).
  static func scheduleOnly(defaults: UserDefaults = .standard, loginState: LoginItem.State = LoginItem.app.state, now: Date = Date()) -> Bool {
    return cannotSurviveRestart(scheduleEnabled: Schedule.isEnabled(in: defaults),
                                hasWindows: Schedule.load(from: defaults).nextStart(after: now) != nil,
                                loginState: loginState)
  }
}
