//
//  IntentTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/23/26.
//  Copyright © 2026 Jake Van Alstyne
//

import XCTest
import AppIntents

/// The Focus rule, the manager's Focus path, and the four intents against a manager of their
/// own (spec 0050).
class IntentTests: XCTestCase {
  private let suite = "OnCueTests.Intents"
  private var defaults: UserDefaults!
  private var manager: RecordingManager!
  private var notified = 0

  override func setUp() {
    super.setUp()
    UserDefaults().removePersistentDomain(forName: suite)
    defaults = UserDefaults(suiteName: suite)
    defaults.set(true, forKey: "motionTriggerEnabled")
    manager = RecordingManager(defaults: defaults)
    manager.deviceAvailabilityChanged(camera: true, microphone: false)
    notified = 0
    manager.onArmedAtLaunch = { [unowned self] in self.notified += 1 }
    IntentTargets.manager = { [unowned self] in self.manager }
  }

  override func tearDown() {
    IntentTargets.manager = nil
    manager.disarm()
    manager = nil
    UserDefaults().removePersistentDomain(forName: suite)
    super.tearDown()
  }

  // MARK: - The rule

  func testAFocusArmsOnlyWhatIsUnarmedAndAble() {
    XCTAssertEqual(FocusArming.action(wantsArmed: true, state: .unarmed, armedByFocus: false, canFire: true), .arm)
    XCTAssertEqual(FocusArming.action(wantsArmed: true, state: .unarmed, armedByFocus: false, canFire: false), .none)
    XCTAssertEqual(FocusArming.action(wantsArmed: true, state: .armed, armedByFocus: false, canFire: true), .none, "armed by someone else: left alone")
    XCTAssertEqual(FocusArming.action(wantsArmed: true, state: .recording, armedByFocus: true, canFire: true), .none)
  }

  func testAFocusEndingDisarmsOnlyWhatAFocusArmed() {
    XCTAssertEqual(FocusArming.action(wantsArmed: false, state: .armed, armedByFocus: true, canFire: true), .disarm)
    XCTAssertEqual(FocusArming.action(wantsArmed: false, state: .arming, armedByFocus: true, canFire: true), .disarm)
    XCTAssertEqual(FocusArming.action(wantsArmed: false, state: .armed, armedByFocus: false, canFire: true), .none, "a manual arm survives")
    XCTAssertEqual(FocusArming.action(wantsArmed: false, state: .unarmed, armedByFocus: false, canFire: true), .none)
  }

  // MARK: - In the manager

  func testAFocusArmsWithTheLaunchCountdownAndTheNotification() {
    manager.focusChanged(wantsArmed: true)
    XCTAssertEqual(manager.state(), .arming)
    XCTAssertEqual(manager.armingCountdown, RecordingManager.launchCountdown)
    XCTAssertTrue(manager.armedByFocus)
    XCTAssertEqual(notified, 1, "arming nobody watched says so")
    manager.focusChanged(wantsArmed: false)
    XCTAssertEqual(manager.state(), .unarmed)
    XCTAssertFalse(manager.armedByFocus)
  }

  func testAFocusEndingLeavesAManualArmAlone() {
    manager.startArming(countdown: 0)
    manager.focusChanged(wantsArmed: true)
    XCTAssertFalse(manager.armedByFocus, "already armed: not the Focus's")
    manager.focusChanged(wantsArmed: false)
    XCTAssertEqual(manager.state(), .armed)
  }

  func testTheStateLineNamesTheFocus() {
    manager.focusChanged(wantsArmed: true)
    for _ in 0..<RecordingManager.launchCountdown { manager.countdown() }
    XCTAssertEqual(manager.state(), .armed)
    XCTAssertTrue(manager.armedStateDescription.hasPrefix("Armed by Focus"), manager.armedStateDescription)
  }

  /// The two flags: each side's end undoes only its own arm.
  func testAFocusAndTheScheduleUndoOnlyTheirOwnArming() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Denver")!
    func date(_ day: Int, _ hour: Int) -> Date {
      calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }
    defaults.set(true, forKey: Schedule.enabledKey)
    Schedule(windows: [ScheduleWindow(days: [2, 3, 4, 5, 6], start: 9 * 60, end: 17 * 60)]).save(to: defaults)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
    // Armed by a Focus inside a window: the window's end leaves it, the Focus's end takes it.
    manager.clock = { date(21, 8) }
    manager.checkSchedule()
    manager.focusChanged(wantsArmed: true)
    XCTAssertTrue(manager.armedByFocus)
    manager.clock = { date(21, 12) }
    manager.checkSchedule()
    XCTAssertFalse(manager.armedBySchedule, "entered a window already armed: not the schedule's")
    manager.clock = { date(21, 17) }
    manager.checkSchedule()
    XCTAssertNotEqual(manager.state(), .unarmed, "the window ending doesn't undo a Focus arm")
    manager.focusChanged(wantsArmed: false)
    XCTAssertEqual(manager.state(), .unarmed)
    // Armed by the schedule: a Focus ending leaves it, the window's end takes it.
    manager.clock = { date(22, 8) }
    manager.checkSchedule()
    manager.clock = { date(22, 9) }
    manager.checkSchedule()
    XCTAssertTrue(manager.armedBySchedule)
    manager.focusChanged(wantsArmed: true)
    XCTAssertFalse(manager.armedByFocus)
    manager.focusChanged(wantsArmed: false)
    XCTAssertNotEqual(manager.state(), .unarmed, "a Focus ending doesn't undo a schedule arm")
    manager.clock = { date(22, 17) }
    manager.checkSchedule()
    XCTAssertEqual(manager.state(), .unarmed)
  }

  // MARK: - The intents

  func testArmIntentArmsLikeTheButton() async throws {
    _ = try await ArmIntent().perform()
    XCTAssertEqual(manager.state(), .arming)
    XCTAssertEqual(manager.armingCountdown, 5, "a person asked: five, like Arm")
    XCTAssertEqual(notified, 0, "and no notification")
  }

  func testArmIntentSaysWhyWhenItCannot() async throws {
    manager.deviceAvailabilityChanged(camera: false, microphone: false)
    _ = try await ArmIntent().perform()
    XCTAssertEqual(manager.state(), .unarmed)
  }

  func testDisarmIntentDisarmsWhateverArmedIt() async throws {
    manager.focusChanged(wantsArmed: true)
    _ = try await DisarmIntent().perform()
    XCTAssertEqual(manager.state(), .unarmed)
  }

  func testIsArmedIntentReturnsTheBoolAndTheLine() async throws {
    var result = try await IsArmedIntent().perform()
    XCTAssertFalse(result.value ?? true)
    manager.startArming(countdown: 3)
    result = try await IsArmedIntent().perform()
    XCTAssertTrue(result.value ?? false, "arming counts as on")
    manager.disarm()
    manager.startArming(countdown: 0)
    result = try await IsArmedIntent().perform()
    XCTAssertTrue(result.value ?? false)
  }

  func testRecordTestIntentRunsTheTest() async throws {
    manager.onTestRecordingWanted = {}
    _ = try await RecordTestIntent().perform()
    XCTAssertEqual(manager.state(), .arming, "from unarmed the test counts down first")
  }

  func testTheFocusFilterReachesTheManager() async throws {
    let filter = ArmFocusFilter()
    filter.armed = true
    _ = try await filter.perform()
    XCTAssertTrue(manager.armedByFocus)
    filter.armed = false
    _ = try await filter.perform()
    XCTAssertEqual(manager.state(), .unarmed)
  }

  func testWithoutAManagerTheIntentsFailCleanly() async {
    IntentTargets.manager = nil
    do {
      _ = try await ArmIntent().perform()
      XCTFail("should have thrown")
    } catch {
      XCTAssertTrue(error is IntentError)
    }
  }
}
