//
//  ArmedRecordTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/23/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import XCTest

/// The trace of being armed that outlives the process, and what a launch does with it (spec 0045).
class ArmedRecordTests: XCTestCase {
  private let suite = "OnCueTests.ArmedRecord"
  private var defaults: UserDefaults!
  private var calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Denver")!
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
  }

  override func tearDown() {
    UserDefaults().removePersistentDomain(forName: suite)
    super.tearDown()
  }

  // MARK: - The record

  func testRoundTripsAndClears() {
    XCTAssertNil(ArmedRecord.read(from: defaults))
    ArmedRecord(lastSeen: date(21, 3, 12), bySchedule: true).write(to: defaults)
    XCTAssertEqual(ArmedRecord.read(from: defaults), ArmedRecord(lastSeen: date(21, 3, 12), bySchedule: true))
    ArmedRecord.clear(in: defaults)
    XCTAssertNil(ArmedRecord.read(from: defaults))
  }

  // MARK: - The launch rule

  func testNoRecordMeansNothingToRecover() {
    XCTAssertNil(ArmedRecord.recovery(from: nil, insideWindowNow: true))
  }

  func testArmedByHandComesBackWhateverTheSchedule() {
    let record = ArmedRecord(lastSeen: date(21, 3), bySchedule: false)
    XCTAssertEqual(ArmedRecord.recovery(from: record, insideWindowNow: false),
                   ArmedRecord.Recovery(rearm: true, bySchedule: false, gapStart: date(21, 3)))
    XCTAssertEqual(ArmedRecord.recovery(from: record, insideWindowNow: true)?.rearm, true)
  }

  func testArmedByScheduleComesBackOnlyInsideAWindow() {
    let record = ArmedRecord(lastSeen: date(21, 10), bySchedule: true)
    XCTAssertEqual(ArmedRecord.recovery(from: record, insideWindowNow: true),
                   ArmedRecord.Recovery(rearm: true, bySchedule: true, gapStart: date(21, 10)))
    XCTAssertEqual(ArmedRecord.recovery(from: record, insideWindowNow: false),
                   ArmedRecord.Recovery(rearm: false, bySchedule: false, gapStart: date(21, 10)),
                   "the window ended while it was down; the gap is still reported")
  }

  // MARK: - In the manager

  private func manager(at moment: Date) -> RecordingManager {
    let manager = RecordingManager(defaults: defaults)
    manager.clock = { moment }
    return manager
  }

  /// A manager past its launch moment with a camera, so arming by hand sticks.
  private func launchedManager(at moment: Date) -> RecordingManager {
    let manager = manager(at: moment)
    manager.deviceAvailabilityChanged(camera: true, microphone: false)
    return manager
  }

  func testArmingWritesTheRecordAndDisarmingClearsIt() {
    let manager = launchedManager(at: date(21, 12))
    XCTAssertNil(ArmedRecord.read(from: defaults))
    manager.startArming(countdown: 0)
    XCTAssertEqual(ArmedRecord.read(from: defaults), ArmedRecord(lastSeen: date(21, 12), bySchedule: false))
    manager.clock = { self.date(21, 12, 1) }
    manager.checkSchedule()
    XCTAssertEqual(ArmedRecord.read(from: defaults)?.lastSeen, date(21, 12, 1), "the minute look refreshes it")
    manager.disarm()
    XCTAssertNil(ArmedRecord.read(from: defaults))
  }

  func testAMinuteLookWhileUnarmedWritesNothing() {
    let manager = launchedManager(at: date(21, 12))
    manager.checkSchedule()
    XCTAssertNil(ArmedRecord.read(from: defaults))
  }

  func testANormalQuitClearsTheRecord() {
    let manager = launchedManager(at: date(21, 12))
    manager.startArming(countdown: 0)
    XCTAssertNotNil(ArmedRecord.read(from: defaults))
    manager.noteNormalQuit()
    XCTAssertNil(ArmedRecord.read(from: defaults))
    manager.disarm()
  }

  func testALaunchAfterADeathSaysSoAndArmsAgain() {
    ArmedRecord(lastSeen: date(21, 3, 12), bySchedule: false).write(to: defaults)
    let manager = manager(at: date(21, 8, 40))
    var saidArming = false
    manager.onArmedAtLaunch = { saidArming = true }
    manager.deviceAvailabilityChanged(camera: true, microphone: false)
    XCTAssertEqual(manager.state(), .arming, "the launch countdown, as arm-at-login does")
    XCTAssertTrue(saidArming)
    XCTAssertEqual(manager.quitUnexpectedlyAt, date(21, 3, 12))
    XCTAssertEqual(manager.quitUnexpectedlyUntil, date(21, 8, 40))
    XCTAssertFalse(manager.armedBySchedule)
    XCTAssertNotNil(ArmedRecord.read(from: defaults), "armed again, so a new record is being kept")
    manager.disarm()
    XCTAssertNil(manager.quitUnexpectedlyUntil, "cleared by the next disarm, like the gap")
  }

  func testRecoveryDoesNotDependOnArmAtLogin() {
    defaults.set(false, forKey: "armAtLogin")
    ArmedRecord(lastSeen: date(21, 3), bySchedule: false).write(to: defaults)
    let manager = manager(at: date(21, 8))
    manager.deviceAvailabilityChanged(camera: true, microphone: false)
    XCTAssertEqual(manager.state(), .arming)
    manager.disarm()
  }

  func testRecoveryHappensOncePerLaunch() {
    ArmedRecord(lastSeen: date(21, 3), bySchedule: false).write(to: defaults)
    let manager = manager(at: date(21, 8))
    manager.deviceAvailabilityChanged(camera: true, microphone: false)
    manager.disarm()
    manager.deviceAvailabilityChanged(camera: true, microphone: true)
    XCTAssertEqual(manager.state(), .unarmed, "devices changing later is not another launch")
    XCTAssertNil(manager.quitUnexpectedlyUntil)
  }

  func testALaunchWithNoRecordChangesNothing() {
    let manager = manager(at: date(21, 8))
    manager.deviceAvailabilityChanged(camera: true, microphone: false)
    XCTAssertEqual(manager.state(), .unarmed)
    XCTAssertNil(manager.quitUnexpectedlyAt)
    XCTAssertNil(manager.quitUnexpectedlyUntil)
  }

  func testScheduledArmingComesBackInsideItsWindow() {
    defaults.set(true, forKey: Schedule.enabledKey)
    Schedule(windows: [ScheduleWindow(days: [2, 3, 4, 5, 6], start: 9 * 60, end: 17 * 60)]).save(to: defaults)
    ArmedRecord(lastSeen: date(21, 10), bySchedule: true).write(to: defaults)
    let manager = manager(at: date(21, 11))
    manager.deviceAvailabilityChanged(camera: true, microphone: false)
    XCTAssertEqual(manager.state(), .arming)
    XCTAssertTrue(manager.armedBySchedule, "so the window's end still disarms it")
    XCTAssertEqual(manager.quitUnexpectedlyAt, date(21, 10))
    manager.disarm()
  }

  func testScheduledArmingStaysDownOutsideAWindowButTheGapIsReported() {
    defaults.set(true, forKey: Schedule.enabledKey)
    Schedule(windows: [ScheduleWindow(days: [2, 3, 4, 5, 6], start: 9 * 60, end: 17 * 60)]).save(to: defaults)
    ArmedRecord(lastSeen: date(21, 16, 50), bySchedule: true).write(to: defaults)
    let manager = manager(at: date(21, 19))
    manager.deviceAvailabilityChanged(camera: true, microphone: false)
    XCTAssertEqual(manager.state(), .unarmed, "the window ended while it was down")
    XCTAssertEqual(manager.quitUnexpectedlyAt, date(21, 16, 50))
    XCTAssertEqual(manager.quitUnexpectedlyUntil, date(21, 19))
    XCTAssertNil(ArmedRecord.read(from: defaults), "the stale record is consumed either way")
  }
}
