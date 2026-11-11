//
//  RecordTestTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/23/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import XCTest

/// A recording started by hand, through the trigger's own path (spec 0046).
class RecordTestTests: XCTestCase {
  private let suite = "OnCueTests.RecordTest"
  private var defaults: UserDefaults!
  private var manager: RecordingManager!
  private var recorder: FakeMovieRecorder!
  private var fired = 0
  private var revealed: [URL] = []

  override func setUp() {
    super.setUp()
    UserDefaults().removePersistentDomain(forName: suite)
    defaults = UserDefaults(suiteName: suite)
    defaults.set(true, forKey: "motionTriggerEnabled")
    manager = RecordingManager(defaults: defaults)
    manager.deviceAvailabilityChanged(camera: true, microphone: false)
    recorder = FakeMovieRecorder()
    fired = 0
    revealed = []
    // Stands in for the capture manager: the trigger's path starts one file on our fake camera.
    manager.onTestRecordingWanted = { [unowned self] in
      self.fired += 1
      self.manager.startRecording(to: self.recorder)
    }
    manager.onTestRecordingFinished = { [unowned self] url in self.revealed.append(url) }
  }

  override func tearDown() {
    manager.disarm()
    manager = nil
    UserDefaults().removePersistentDomain(forName: suite)
    super.tearDown()
  }

  private func finishTheFile(error: Error? = nil) {
    manager.recordingDidFinish(url: recorder.startedURLs.last!, error: error)
  }

  // MARK: - The rules

  func testTheCountdownCoversThePreRollAndNeverUnderArms() {
    XCTAssertEqual(RecordingManager.testCountdown(preRollSeconds: 0), 5)
    XCTAssertEqual(RecordingManager.testCountdown(preRollSeconds: 5), 5)
    XCTAssertEqual(RecordingManager.testCountdown(preRollSeconds: 7.5), 8)
    XCTAssertEqual(RecordingManager.testCountdown(preRollSeconds: 30), 30)
  }

  func testOfferedWhenArmWouldBeOrWhileArmed() {
    XCTAssertTrue(RecordingManager.canRecordTest(state: .unarmed, canArm: true))
    XCTAssertFalse(RecordingManager.canRecordTest(state: .unarmed, canArm: false))
    XCTAssertTrue(RecordingManager.canRecordTest(state: .armed, canArm: true))
    XCTAssertFalse(RecordingManager.canRecordTest(state: .arming, canArm: true))
    XCTAssertFalse(RecordingManager.canRecordTest(state: .recording, canArm: true))
  }

  // MARK: - From armed

  func testFromArmedItRecordsAtOnceAndStaysArmed() {
    manager.startArming(countdown: 0)
    manager.recordTest()
    XCTAssertEqual(fired, 1)
    XCTAssertEqual(manager.state(), .recording)
    XCTAssertTrue(manager.isRecordingTest)
    finishTheFile()
    XCTAssertEqual(manager.state(), .armed, "armed before, armed after")
    XCTAssertFalse(manager.isRecordingTest)
    XCTAssertEqual(revealed, [recorder.startedURLs[0]])
  }

  // MARK: - From unarmed

  func testFromUnarmedItCountsDownRecordsAndDisarms() {
    manager.recordTest()
    XCTAssertEqual(manager.state(), .arming)
    XCTAssertEqual(manager.armingCountdown, 5, "the default pre-roll needs no more than Arm's five")
    XCTAssertEqual(fired, 0, "nothing until the ring has filled")
    for _ in 0..<5 { manager.countdown() }
    XCTAssertEqual(fired, 1)
    XCTAssertEqual(manager.state(), .recording)
    finishTheFile()
    XCTAssertEqual(manager.state(), .unarmed, "unarmed before, unarmed after")
    XCTAssertFalse(manager.isRecordingTest)
    XCTAssertEqual(revealed.count, 1)
  }

  func testALongerPreRollGetsALongerCountdown() {
    defaults.set(20.0, forKey: "preRollSeconds")
    manager.recordTest()
    XCTAssertEqual(manager.armingCountdown, 20)
  }

  // MARK: - What it finds

  func testAFailedTestKeepsItsNoticeThroughTheCleanup() {
    manager.recordTest()
    for _ in 0..<5 { manager.countdown() }
    XCTAssertEqual(manager.state(), .recording)
    finishTheFile(error: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)))
    XCTAssertEqual(manager.state(), .unarmed)
    XCTAssertEqual(manager.recordingFailure, .diskFull, "the reason the person pressed the button")
    XCTAssertEqual(manager.recordingFailureCount, 1)
    XCTAssertTrue(revealed.isEmpty, "nothing to show")
    manager.disarm()
    XCTAssertNil(manager.recordingFailure, "an ordinary disarm still clears it")
  }

  func testARecordingThatIsRefusedEndsTheTest() {
    // Capture answers with nothing to record on.
    manager.onTestRecordingWanted = { [unowned self] in self.fired += 1; self.manager.startRecording(to: []) }
    manager.recordTest()
    for _ in 0..<5 { manager.countdown() }
    XCTAssertEqual(fired, 1)
    XCTAssertEqual(manager.state(), .unarmed, "armed for the test, and put back")
    XCTAssertFalse(manager.isRecordingTest)
  }

  /// From unarmed with the popover closed, the cameras start after arming: capture answers later.
  func testCaptureMayAnswerLater() {
    manager.onTestRecordingWanted = { [unowned self] in self.fired += 1 }  // still starting
    manager.recordTest()
    for _ in 0..<5 { manager.countdown() }
    XCTAssertEqual(manager.state(), .armed)
    XCTAssertTrue(manager.isRecordingTest, "waiting for capture, not given up")
    manager.startRecording(to: recorder)
    XCTAssertEqual(manager.state(), .recording)
    finishTheFile()
    XCTAssertEqual(manager.state(), .unarmed)
    XCTAssertFalse(manager.isRecordingTest)
    XCTAssertEqual(revealed.count, 1)
  }

  func testDisarmingByHandMidTestEndsIt() {
    manager.startArming(countdown: 0)
    manager.recordTest()
    manager.disarm()
    XCTAssertFalse(manager.isRecordingTest)
    finishTheFile()
    XCTAssertTrue(revealed.isEmpty, "a file finishing after a manual disarm is an ordinary file")
    XCTAssertEqual(manager.state(), .unarmed)
  }

  func testASecondPressDuringATestDoesNothing() {
    manager.startArming(countdown: 0)
    manager.recordTest()
    manager.recordTest()
    XCTAssertEqual(fired, 1)
  }
}
