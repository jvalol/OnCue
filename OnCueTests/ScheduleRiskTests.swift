//
//  ScheduleRiskTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/23/26.
//  Copyright © 2026 Jake Van Alstyne
//

import XCTest

/// When a schedule can't survive a restart (spec 0051): on, with something coming, and OnCue not
/// opening at login. Arming at login has the same shape (spec 0060).
class ScheduleRiskTests: XCTestCase {
  func testOnWithWindowsAndLoginOffIsTheRisk() {
    XCTAssertTrue(ScheduleRisk.cannotSurviveRestart(scheduleEnabled: true, hasWindows: true, loginState: .off))
    XCTAssertTrue(ScheduleRisk.cannotSurviveRestart(scheduleEnabled: true, hasWindows: true, loginState: .needsApproval),
                  "switched off in System Settings is off")
  }

  func testLoginOnClearsIt() {
    XCTAssertFalse(ScheduleRisk.cannotSurviveRestart(scheduleEnabled: true, hasWindows: true, loginState: .on))
  }

  func testNoScheduleOrNothingComingIsNoRisk() {
    XCTAssertFalse(ScheduleRisk.cannotSurviveRestart(scheduleEnabled: false, hasWindows: true, loginState: .off))
    XCTAssertFalse(ScheduleRisk.cannotSurviveRestart(scheduleEnabled: true, hasWindows: false, loginState: .off), "rows with no days or no length")
  }

  func testFromTheAppsOwnState() {
    let suite = "OnCueTests.ScheduleRisk"
    UserDefaults().removePersistentDomain(forName: suite)
    let defaults = UserDefaults(suiteName: suite)!
    XCTAssertFalse(ScheduleRisk.current(defaults: defaults, loginState: .off), "no schedule")
    defaults.set(true, forKey: Schedule.enabledKey)
    XCTAssertFalse(ScheduleRisk.current(defaults: defaults, loginState: .off), "on, but no windows")
    Schedule(windows: [ScheduleWindow(days: [2, 3, 4, 5, 6], start: 9 * 60, end: 17 * 60)]).save(to: defaults)
    XCTAssertTrue(ScheduleRisk.current(defaults: defaults, loginState: .off))
    XCTAssertFalse(ScheduleRisk.current(defaults: defaults, loginState: .on))
    UserDefaults().removePersistentDomain(forName: suite)
  }

  // MARK: - Arming at login (spec 0060)

  func testArmAtLoginAloneIsTheRisk() {
    XCTAssertTrue(ScheduleRisk.cannotSurviveRestart(scheduleEnabled: false, hasWindows: false, armAtLogin: true, loginState: .off))
    XCTAssertTrue(ScheduleRisk.cannotSurviveRestart(scheduleEnabled: false, hasWindows: false, armAtLogin: true, loginState: .needsApproval))
    XCTAssertFalse(ScheduleRisk.cannotSurviveRestart(scheduleEnabled: false, hasWindows: false, armAtLogin: true, loginState: .on),
                   "Open at Login on: nothing to say")
    XCTAssertFalse(ScheduleRisk.cannotSurviveRestart(scheduleEnabled: false, hasWindows: false, armAtLogin: false, loginState: .off),
                   "neither reason: nothing to say")
  }

  func testBothReasonsAreStillOneRisk() {
    XCTAssertTrue(ScheduleRisk.cannotSurviveRestart(scheduleEnabled: true, hasWindows: true, armAtLogin: true, loginState: .off))
    XCTAssertFalse(ScheduleRisk.cannotSurviveRestart(scheduleEnabled: true, hasWindows: true, armAtLogin: true, loginState: .on))
  }

  func testArmAtLoginFromTheAppsOwnState() {
    let suite = "OnCueTests.ScheduleRisk.armAtLogin"
    UserDefaults().removePersistentDomain(forName: suite)
    let defaults = UserDefaults(suiteName: suite)!
    XCTAssertFalse(ScheduleRisk.current(defaults: defaults, loginState: .off), "arm at login off by default")
    defaults.set(true, forKey: "armAtLogin")
    XCTAssertTrue(ScheduleRisk.current(defaults: defaults, loginState: .off))
    XCTAssertFalse(ScheduleRisk.current(defaults: defaults, loginState: .on))
    defaults.set(false, forKey: "armAtLogin")
    XCTAssertFalse(ScheduleRisk.current(defaults: defaults, loginState: .off), "turned off again")
    UserDefaults().removePersistentDomain(forName: suite)
  }

  /// The note under the schedule in Settings talks about the schedule, so it ignores the arm box.
  func testSettingsNoteIgnoresArmAtLogin() {
    let suite = "OnCueTests.ScheduleRisk.scheduleOnly"
    UserDefaults().removePersistentDomain(forName: suite)
    let defaults = UserDefaults(suiteName: suite)!
    defaults.set(true, forKey: "armAtLogin")
    XCTAssertFalse(ScheduleRisk.scheduleOnly(defaults: defaults, loginState: .off))
    XCTAssertTrue(ScheduleRisk.current(defaults: defaults, loginState: .off), "but the popover says so")
    defaults.set(true, forKey: Schedule.enabledKey)
    Schedule(windows: [ScheduleWindow(days: [2, 3, 4, 5, 6], start: 9 * 60, end: 17 * 60)]).save(to: defaults)
    XCTAssertTrue(ScheduleRisk.scheduleOnly(defaults: defaults, loginState: .off))
    UserDefaults().removePersistentDomain(forName: suite)
  }
}
