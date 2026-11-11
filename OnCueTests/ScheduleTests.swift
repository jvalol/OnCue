//
//  ScheduleTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/22/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import XCTest

class ScheduleTests: XCTestCase {
  private var calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Denver")!
    return c
  }()

  /// 2026-09-21 is a Monday.
  private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    return calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
  }

  private let weekdays: Set<Int> = [2, 3, 4, 5, 6]
  private let nineToFive = ScheduleWindow(days: [2, 3, 4, 5, 6], start: 9 * 60, end: 17 * 60)
  private let overnight = ScheduleWindow(days: [6], start: 22 * 60, end: 6 * 60)  // Friday night

  func testInsideAWindowOnAChosenDay() {
    XCTAssertTrue(nineToFive.contains(date(21, 12), calendar: calendar))
  }

  func testStartIsInclusiveAndEndIsExclusive() {
    XCTAssertTrue(nineToFive.contains(date(21, 9, 0), calendar: calendar))
    XCTAssertFalse(nineToFive.contains(date(21, 8, 59), calendar: calendar))
    XCTAssertFalse(nineToFive.contains(date(21, 17, 0), calendar: calendar))
    XCTAssertTrue(nineToFive.contains(date(21, 16, 59), calendar: calendar))
  }

  func testADayNotChosenIsOutside() {
    XCTAssertFalse(nineToFive.contains(date(20, 12), calendar: calendar), "Sunday")
    XCTAssertFalse(nineToFive.contains(date(26, 12), calendar: calendar), "Saturday")
  }

  /// A window that crosses midnight belongs to the day it starts on: Friday night runs into
  /// Saturday morning even though Saturday isn't chosen, and Thursday night stays out even though
  /// Friday is.
  func testAWindowCrossingMidnightBelongsToTheDayItStartsOn() {
    XCTAssertTrue(overnight.contains(date(25, 23), calendar: calendar), "Friday 23:00")
    XCTAssertTrue(overnight.contains(date(26, 3), calendar: calendar), "Saturday 03:00")
    XCTAssertFalse(overnight.contains(date(26, 6, 0), calendar: calendar), "Saturday 06:00, over")
    XCTAssertFalse(overnight.contains(date(26, 23), calendar: calendar), "Saturday night, not chosen")
    XCTAssertFalse(overnight.contains(date(25, 3), calendar: calendar), "Friday 03:00 is Thursday's night")
  }

  func testSundayNightRunsIntoMondayMorning() {
    let sunday = ScheduleWindow(days: [1], start: 22 * 60, end: 6 * 60)
    XCTAssertTrue(sunday.contains(date(21, 2), calendar: calendar), "Monday 02:00")
  }

  func testAZeroLengthWindowIsNothing() {
    let empty = ScheduleWindow(days: [2], start: 9 * 60, end: 9 * 60)
    XCTAssertFalse(empty.contains(date(21, 9), calendar: calendar))
  }

  func testTheEndOfTheWindowContainingAMoment() {
    XCTAssertEqual(nineToFive.end(of: date(21, 12), calendar: calendar), date(21, 17))
    XCTAssertEqual(overnight.end(of: date(25, 23), calendar: calendar), date(26, 6), "evening half ends tomorrow")
    XCTAssertEqual(overnight.end(of: date(26, 3), calendar: calendar), date(26, 6), "morning half ends today")
    XCTAssertNil(nineToFive.end(of: date(21, 18), calendar: calendar))
  }

  func testAScheduleIsInsideIfAnyWindowIs() {
    let schedule = Schedule(windows: [nineToFive, overnight])
    XCTAssertTrue(schedule.contains(date(21, 12), calendar: calendar))
    XCTAssertTrue(schedule.contains(date(26, 3), calendar: calendar))
    XCTAssertFalse(schedule.contains(date(21, 20), calendar: calendar))
    XCTAssertFalse(Schedule().contains(date(21, 12), calendar: calendar), "no windows, never inside")
  }

  /// Overlapping rows just mean armed, and the popover names the later end.
  func testOverlappingWindowsEndWithTheLaterOne() {
    let short = ScheduleWindow(days: [2], start: 10 * 60, end: 14 * 60)
    let schedule = Schedule(windows: [short, nineToFive])
    XCTAssertEqual(schedule.end(of: date(21, 12), calendar: calendar), date(21, 17))
  }

  func testRoundTripsThroughDefaults() {
    let suite = "OnCueTests.Schedule"
    UserDefaults().removePersistentDomain(forName: suite)
    let defaults = UserDefaults(suiteName: suite)!
    XCTAssertEqual(Schedule.load(from: defaults), Schedule())
    let schedule = Schedule(windows: [nineToFive, overnight])
    schedule.save(to: defaults)
    XCTAssertEqual(Schedule.load(from: defaults), schedule)
    UserDefaults().removePersistentDomain(forName: suite)
  }

  // MARK: - The transition rule

  func testEnteringAWindowArms() {
    XCTAssertEqual(Schedule.action(enabled: true, insideNow: true, insideBefore: false, state: .unarmed,
                                   armedBySchedule: false, canFire: true), .arm)
  }

  /// The first look after launch, or after the schedule changed, counts a window already under way
  /// as entered. That's what arms on launch and on a wake that crossed a window's start.
  func testTheFirstLookInsideAWindowArms() {
    XCTAssertEqual(Schedule.action(enabled: true, insideNow: true, insideBefore: nil, state: .unarmed,
                                   armedBySchedule: false, canFire: true), .arm)
    XCTAssertEqual(Schedule.action(enabled: true, insideNow: false, insideBefore: nil, state: .unarmed,
                                   armedBySchedule: false, canFire: true), .none)
  }

  func testStayingInsideDoesNothingSoAManualDisarmHolds() {
    XCTAssertEqual(Schedule.action(enabled: true, insideNow: true, insideBefore: true, state: .unarmed,
                                   armedBySchedule: false, canFire: true), .none)
  }

  func testLeavingAWindowDisarmsOnlyWhatTheScheduleArmed() {
    XCTAssertEqual(Schedule.action(enabled: true, insideNow: false, insideBefore: true, state: .armed,
                                   armedBySchedule: true, canFire: true), .disarm)
    XCTAssertEqual(Schedule.action(enabled: true, insideNow: false, insideBefore: true, state: .armed,
                                   armedBySchedule: false, canFire: true), .none, "armed by hand")
    XCTAssertEqual(Schedule.action(enabled: true, insideNow: false, insideBefore: true, state: .unarmed,
                                   armedBySchedule: false, canFire: true), .none, "nothing to disarm")
  }

  func testEnteringWhileAlreadyArmedByHandDoesNothing() {
    XCTAssertEqual(Schedule.action(enabled: true, insideNow: true, insideBefore: false, state: .armed,
                                   armedBySchedule: false, canFire: true), .none)
  }

  func testNothingArmsWhenNoTriggerCanFire() {
    XCTAssertEqual(Schedule.action(enabled: true, insideNow: true, insideBefore: false, state: .unarmed,
                                   armedBySchedule: false, canFire: false), .none)
  }

  func testASwitchedOffScheduleDoesNothingEitherWay() {
    XCTAssertEqual(Schedule.action(enabled: false, insideNow: true, insideBefore: false, state: .unarmed,
                                   armedBySchedule: false, canFire: true), .none)
    XCTAssertEqual(Schedule.action(enabled: false, insideNow: false, insideBefore: true, state: .armed,
                                   armedBySchedule: true, canFire: true), .none)
  }

  // MARK: - The next start (spec 0044)

  func testNextStartLaterToday() {
    XCTAssertEqual(nineToFive.nextStart(after: date(21, 8, 59), calendar: calendar), date(21, 9))
  }

  func testNextStartInsideAWindowIsTheFollowingDay() {
    XCTAssertEqual(nineToFive.nextStart(after: date(21, 12), calendar: calendar), date(22, 9))
    XCTAssertEqual(nineToFive.nextStart(after: date(21, 9, 0), calendar: calendar), date(22, 9), "a start already passed doesn't count")
  }

  func testNextStartSkipsTheWeekend() {
    XCTAssertEqual(nineToFive.nextStart(after: date(25, 18), calendar: calendar), date(28, 9), "Friday evening to Monday")
    XCTAssertEqual(nineToFive.nextStart(after: date(26, 12), calendar: calendar), date(28, 9), "Saturday to Monday")
  }

  func testNextStartOfAnOvernightWindowIsItsEveningStart() {
    let nextFriday = calendar.date(byAdding: .day, value: 7, to: date(25, 22))!
    XCTAssertEqual(overnight.nextStart(after: date(26, 3), calendar: calendar), nextFriday,
                   "Saturday 3am, inside Friday's window: the next start is next Friday")
  }

  func testNothingComingIsNil() {
    XCTAssertNil(ScheduleWindow(days: [], start: 9 * 60, end: 17 * 60).nextStart(after: date(21, 8), calendar: calendar))
    XCTAssertNil(ScheduleWindow(days: [2], start: 9 * 60, end: 9 * 60).nextStart(after: date(21, 8), calendar: calendar), "zero length")
    XCTAssertNil(Schedule().nextStart(after: date(21, 8), calendar: calendar))
  }

  func testTheScheduleTakesTheEarliestStartAcrossWindows() {
    let schedule = Schedule(windows: [nineToFive, ScheduleWindow(days: [7], start: 8 * 60, end: 12 * 60)])
    XCTAssertEqual(schedule.nextStart(after: date(25, 18), calendar: calendar), date(26, 8), "Saturday morning beats Monday")
  }
}

/// The schedule driving a real RecordingManager, with a fake clock and its own defaults.
class ScheduledArmingTests: XCTestCase {
  private let suite = "OnCueTests.ScheduledArming"
  private var defaults: UserDefaults!
  private var manager: RecordingManager!
  private var calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Denver")!
    // Without a locale the calendar's weekday names are the short ones ("Thu"); the app's
    // Calendar.current has one.
    c.locale = Locale(identifier: "en_US")
    return c
  }()

  /// 2026-09-21 is a Monday.
  private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    return calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
  }

  override func setUp() {
    super.setUp()
    UserDefaults().removePersistentDomain(forName: suite)
    defaults = UserDefaults(suiteName: suite)
    defaults.set(true, forKey: "motionTriggerEnabled")
    defaults.set(true, forKey: Schedule.enabledKey)
    Schedule(windows: [ScheduleWindow(days: [2, 3, 4, 5, 6], start: 9 * 60, end: 17 * 60)]).save(to: defaults)
    manager = RecordingManager(defaults: defaults)
  }

  override func tearDown() {
    manager.disarm()
    manager = nil
    UserDefaults().removePersistentDomain(forName: suite)
    super.tearDown()
  }

  /// Devices arriving is the launch moment, the same one arm-at-login uses.
  private func launch(at moment: Date, camera: Bool = true) {
    manager.clock = { moment }
    manager.deviceAvailabilityChanged(camera: camera, microphone: false)
  }

  private func tick(_ moment: Date) {
    manager.clock = { moment }
    manager.checkSchedule()
  }

  func testLaunchingInsideAWindowArms() {
    launch(at: date(21, 12))
    XCTAssertEqual(manager.state(), .arming, "the launch countdown, not an instant arm")
    XCTAssertTrue(manager.armedBySchedule)
  }

  func testLaunchingOutsideAWindowDoesNothing() {
    launch(at: date(21, 20))
    XCTAssertEqual(manager.state(), .unarmed)
  }

  func testEnteringAndLeavingAWindow() {
    launch(at: date(21, 8, 59))
    XCTAssertEqual(manager.state(), .unarmed)
    tick(date(21, 9, 0))
    XCTAssertEqual(manager.state(), .arming)
    XCTAssertTrue(manager.armedBySchedule)
    tick(date(21, 17, 0))
    XCTAssertEqual(manager.state(), .unarmed)
    XCTAssertFalse(manager.armedBySchedule)
  }

  func testAManualDisarmInsideAWindowHoldsUntilTheNextOne() {
    launch(at: date(21, 12))
    manager.disarm()
    tick(date(21, 12, 1))
    tick(date(21, 15))
    XCTAssertEqual(manager.state(), .unarmed, "not re-armed the same window")
    tick(date(21, 17))
    tick(date(22, 9))
    XCTAssertEqual(manager.state(), .arming, "the next window starts fresh")
  }

  func testAManualArmOutsideAWindowIsLeftAlone() {
    launch(at: date(21, 20))
    manager.startArming(countdown: 0)
    XCTAssertEqual(manager.state(), .armed)
    tick(date(22, 12))
    tick(date(22, 17))
    XCTAssertEqual(manager.state(), .armed, "a window's end disarms only what the schedule armed")
    XCTAssertFalse(manager.armedBySchedule)
  }

  func testWakingInsideAWindowThatStartedDuringSleepArms() {
    launch(at: date(21, 8))
    manager.systemDidWake(at: date(21, 9, 30))
    XCTAssertEqual(manager.state(), .arming)
  }

  func testWakingAfterAManualDisarmStaysDisarmed() {
    launch(at: date(21, 12))
    manager.disarm()
    manager.systemDidWake(at: date(21, 12, 30))
    XCTAssertEqual(manager.state(), .unarmed)
  }

  func testNothingArmsWhenNoTriggerCanFire() {
    launch(at: date(21, 12), camera: false)
    XCTAssertEqual(manager.state(), .unarmed)
  }

  func testTheEndIsNamedByDayWhenItIsntToday() {
    let today = RecordingManager.describe(end: date(21, 17), now: date(21, 12), calendar: calendar)
    XCTAssertFalse(today.contains("tomorrow") || today.contains("Monday"))
    XCTAssertTrue(RecordingManager.describe(end: date(22, 17), now: date(21, 19), calendar: calendar).contains("tomorrow"))
    XCTAssertTrue(RecordingManager.describe(end: date(24, 6), now: date(21, 19), calendar: calendar).contains("Thursday"))
  }

  func testTheWindowEndIsNamedOnlyWhileArmedBySchedule() {
    launch(at: date(21, 12))
    XCTAssertEqual(manager.scheduledWindowEnd(), date(21, 17))
    manager.disarm()
    XCTAssertNil(manager.scheduledWindowEnd())
  }

  /// Changing the schedule while inside a new window arms; it's a fresh look at fresh rows.
  func testChangingTheScheduleTakesEffectAtOnce() {
    launch(at: date(21, 20))
    XCTAssertEqual(manager.state(), .unarmed)
    Schedule(windows: [ScheduleWindow(days: [2], start: 19 * 60, end: 22 * 60)]).save(to: defaults)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
    XCTAssertEqual(manager.state(), .arming)
  }

  // MARK: - Staying awake for the schedule (spec 0044)

  func testTheScheduleKeepsTheMacAwakeBetweenWindows() {
    launch(at: date(21, 20))
    XCTAssertEqual(manager.state(), .unarmed)
    XCTAssertTrue(manager.isKeepingAwake)
    XCTAssertEqual(manager.keepingAwakeFor, .schedule)
  }

  func testArmedWinsOverTheScheduleAsTheReason() {
    launch(at: date(21, 12))
    XCTAssertEqual(manager.keepingAwakeFor, .armed)
    tick(date(21, 17))
    XCTAssertEqual(manager.state(), .unarmed)
    XCTAssertEqual(manager.keepingAwakeFor, .schedule, "the window ended; the next one is coming")
  }

  func testAManualDisarmInsideAWindowKeepsTheMacAwake() {
    launch(at: date(21, 12))
    manager.disarm()
    XCTAssertEqual(manager.state(), .unarmed)
    XCTAssertTrue(manager.isKeepingAwake)
    XCTAssertEqual(manager.keepingAwakeFor, .schedule)
  }

  func testSwitchingTheScheduleOffLetsTheMacSleep() {
    launch(at: date(21, 20))
    XCTAssertTrue(manager.isKeepingAwake)
    defaults.set(false, forKey: Schedule.enabledKey)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
    XCTAssertFalse(manager.isKeepingAwake)
    XCTAssertNil(manager.keepingAwakeFor)
  }

  func testAScheduleWithNothingComingLetsTheMacSleep() {
    Schedule(windows: [ScheduleWindow(days: [], start: 9 * 60, end: 17 * 60)]).save(to: defaults)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
    launch(at: date(21, 20))
    XCTAssertFalse(manager.isKeepingAwake)
  }

  func testTheReasonRuleAlone() {
    XCTAssertEqual(RecordingManager.keepAwakeReason(state: .armed, scheduleEnabled: true, nextStart: Date()), .armed)
    XCTAssertEqual(RecordingManager.keepAwakeReason(state: .arming, scheduleEnabled: false, nextStart: nil), .armed)
    XCTAssertEqual(RecordingManager.keepAwakeReason(state: .unarmed, scheduleEnabled: true, nextStart: Date()), .schedule)
    XCTAssertNil(RecordingManager.keepAwakeReason(state: .unarmed, scheduleEnabled: true, nextStart: nil))
    XCTAssertNil(RecordingManager.keepAwakeReason(state: .unarmed, scheduleEnabled: false, nextStart: Date()))
    XCTAssertNil(RecordingManager.keepAwakeReason(state: nil, scheduleEnabled: false, nextStart: nil))
  }

  func testUnarmedNamesTheNextWindow() {
    launch(at: date(21, 20))
    XCTAssertTrue(manager.armedStateDescription.hasPrefix("Unarmed until"), manager.armedStateDescription)
    XCTAssertTrue(manager.armedStateDescription.contains("tomorrow"), manager.armedStateDescription)
    tick(date(25, 18))
    XCTAssertTrue(manager.armedStateDescription.contains("Monday"), manager.armedStateDescription)
    tick(date(28, 8))
    XCTAssertFalse(manager.armedStateDescription.contains("Monday"), "later today is the time alone: \(manager.armedStateDescription)")
  }

  func testUnarmedIsPlainWithTheScheduleOff() {
    defaults.set(false, forKey: Schedule.enabledKey)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
    launch(at: date(21, 20))
    XCTAssertEqual(manager.armedStateDescription, "Unarmed")
  }
}
