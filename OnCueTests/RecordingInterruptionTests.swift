//
//  RecordingInterruptionTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/19/26.
//  Copyright © 2026 Jake Van Alstyne
//

import XCTest
import AVFoundation

/// Stands in for a camera's recorder so recording state can be tested without a camera.
class FakeMovieRecorder: MovieRecorder {
  private(set) var startedURLs: [URL] = []
  private(set) var rolledURLs: [URL] = []
  private(set) var stopCount = 0
  var footageStart = Date()
  /// Held so a test can finish a rolled file the way the real recorder eventually does.
  private(set) var rollFinishers: [(URL, Error?) -> Void] = []

  func startRecording(to url: URL, onFinish: @escaping (URL, Error?) -> Void) {
    startedURLs.append(url)
  }

  func roll(to url: URL, onFinish: @escaping (URL, Error?) -> Void) {
    rolledURLs.append(url)
    rollFinishers.append(onFinish)
  }

  func stopRecording() {
    stopCount += 1
  }
}

class RecordingInterruptionTests: XCTestCase {
  var recordingManager: RecordingManager!
  var recorder: FakeMovieRecorder!

  override func setUp() {
    recordingManager = RecordingManager()
    recorder = FakeMovieRecorder()
    recordingManager.startArming(countdown: 0)
  }

  // MARK: - Keeping the disk promises during a recording (spec 0031)

  /// The old file closing must not read as the recording having ended, because a new one is
  /// already open. Getting this wrong would return OnCue to armed mid-event.
  func testRollingCarriesTheRecordingOn() {
    recordingManager.startRecording(to: recorder)
    recordingManager.rollRecording()

    XCTAssertEqual(recorder.rolledURLs.count, 1)
    recordingManager.recordingDidFinish(url: recorder.startedURLs[0], error: nil)
    XCTAssertEqual(recordingManager.state(), .recording)
  }

  /// And it does end once the rolled file finishes too, so nothing is left believing it is
  /// recording after everything has closed.
  func testTheRecordingEndsOnceTheRolledFileFinishesToo() {
    recordingManager.startRecording(to: recorder)
    recordingManager.rollRecording()

    recordingManager.recordingDidFinish(url: recorder.startedURLs[0], error: nil)
    recordingManager.recordingDidFinish(url: recorder.rolledURLs[0], error: nil)
    XCTAssertEqual(recordingManager.state(), .armed)
  }

  /// Stopping for space finishes the file, so what was already written survives.
  func testStoppingForSpaceEndsTheFileRatherThanAbandoningIt() {
    recordingManager.startRecording(to: recorder)
    recordingManager.stopForLackOfSpace()
    XCTAssertEqual(recorder.stopCount, 1)
  }

  /// The reason has to survive the clean finish. A recording that ends without error clears the
  /// last failure, so noting this before the files closed would wipe it.
  func testStoppingForSpaceSaysWhyAfterTheFileCloses() {
    recordingManager.startRecording(to: recorder)
    recordingManager.stopForLackOfSpace()
    XCTAssertNil(recordingManager.recordingFailure, "not yet: the file is still closing")

    recordingManager.recordingDidFinish(url: recorder.startedURLs[0], error: nil)
    XCTAssertEqual(recordingManager.recordingFailure, .diskFull)
  }

  /// Asking twice does not stop twice, so a check every thirty seconds during a long close is
  /// harmless.
  func testStoppingForSpaceOnlyHappensOnce() {
    recordingManager.startRecording(to: recorder)
    recordingManager.stopForLackOfSpace()
    recordingManager.stopForLackOfSpace()
    XCTAssertEqual(recorder.stopCount, 1)
  }

  func testSuspendingARecordingEndsTheFileAndReturnsToArmed() {
    recordingManager.startRecording(to: recorder)

    XCTAssertTrue(recordingManager.suspendRecording())
    XCTAssertEqual(recordingManager.state(), .armed)
    XCTAssertEqual(recorder.stopCount, 1)
  }

  func testSuspendingWhileArmedDoesNothing() {
    XCTAssertFalse(recordingManager.suspendRecording())
    XCTAssertEqual(recordingManager.state(), .armed)
    XCTAssertEqual(recorder.stopCount, 0)
  }

  func testResumingStartsANewFile() {
    recordingManager.startRecording(to: recorder)
    XCTAssertTrue(recordingManager.suspendRecording())

    recordingManager.startRecording(to: recorder)

    XCTAssertEqual(recordingManager.state(), .recording)
    XCTAssertEqual(recorder.startedURLs.count, 2)
  }

  func testDisarmDuringAnInterruptionWins() {
    recordingManager.startRecording(to: recorder)
    XCTAssertTrue(recordingManager.suspendRecording())

    recordingManager.disarm()
    recordingManager.startRecording(to: recorder)

    XCTAssertEqual(recordingManager.state(), .unarmed)
    XCTAssertEqual(recorder.startedURLs.count, 1)
  }

  func testAFileEndingOnItsOwnReturnsToArmed() {
    recordingManager.startRecording(to: recorder)
    let url = recorder.startedURLs[0]

    recordingManager.recordingDidFinish(url: url.absoluteURL, error: NSError(domain: AVFoundationErrorDomain, code: AVError.diskFull.rawValue))

    XCTAssertEqual(recordingManager.state(), .armed)
  }

  func testAnEarlierFileFinishingLateLeavesTheNewRecordingAlone() {
    recordingManager.startRecording(to: recorder)
    let firstURL = recorder.startedURLs[0]
    XCTAssertTrue(recordingManager.suspendRecording())
    recordingManager.startRecording(to: recorder)

    recordingManager.recordingDidFinish(url: firstURL, error: nil)

    XCTAssertEqual(recordingManager.state(), .recording)
  }

  func testAFileStoppedOnPurposeChangesNothingWhenItFinishes() {
    recordingManager.startRecording(to: recorder)
    let url = recorder.startedURLs[0]
    recordingManager.stopRecording(recorder)

    recordingManager.recordingDidFinish(url: url, error: nil)

    XCTAssertEqual(recordingManager.state(), .armed)
  }
}

class TwoCameraRecordingTests: XCTestCase {
  var recordingManager: RecordingManager!
  var first: FakeMovieRecorder!
  var second: FakeMovieRecorder!

  override func setUp() {
    recordingManager = RecordingManager()
    first = FakeMovieRecorder()
    second = FakeMovieRecorder()
    recordingManager.startArming(countdown: 0)
    recordingManager.startRecording(to: [RecordingTarget(recorder: first, cameraName: "MacBook Pro Camera", microphoneName: "Mic"),
                                         RecordingTarget(recorder: second, cameraName: "Webcam", microphoneName: "Mic")])
  }

  func testAFileIsNamedForWhenItsFootageBegins() {
    let manager = RecordingManager()
    let recorder = FakeMovieRecorder()
    var components = DateComponents(year: 2026, month: 9, day: 19, hour: 13, minute: 30, second: 5)
    components.timeZone = TimeZone.current
    recorder.footageStart = Calendar.current.date(from: components)!
    manager.startArming(countdown: 0)

    manager.startRecording(to: recorder, cameraName: "Webcam")

    XCTAssertTrue(recorder.startedURLs[0].lastPathComponent.hasPrefix("2026-09-19 13.30.05"))
  }

  func testEachCameraRecordsItsOwnFileNamedForIt() {
    XCTAssertEqual(first.startedURLs.count, 1)
    XCTAssertEqual(second.startedURLs.count, 1)
    XCTAssertTrue(first.startedURLs[0].lastPathComponent.contains("MacBook Pro Camera"))
    XCTAssertTrue(second.startedURLs[0].lastPathComponent.contains("Webcam"))
  }

  func testStoppingEndsBothFiles() {
    recordingManager.stopRecording()
    XCTAssertEqual(first.stopCount, 1)
    XCTAssertEqual(second.stopCount, 1)
    XCTAssertEqual(recordingManager.state(), .armed)
  }

  func testOneFileEndingOnItsOwnLeavesTheOtherRecording() {
    recordingManager.recordingDidFinish(url: first.startedURLs[0], error: nil)
    XCTAssertEqual(recordingManager.state(), .recording)

    recordingManager.recordingDidFinish(url: second.startedURLs[0], error: nil)
    XCTAssertEqual(recordingManager.state(), .armed)
  }

  func testQuittingWaitsOnlyWhileRecording() {
    XCTAssertTrue(RecordingManager.waitsBeforeQuitting(isRecording: true))
    XCTAssertFalse(RecordingManager.waitsBeforeQuitting(isRecording: false))
  }

  func testTellsWhenEveryFileHasFinished() {
    var finished = 0
    recordingManager.onRecordingsFinished = { finished += 1 }

    recordingManager.recordingDidFinish(url: first.startedURLs[0], error: nil)
    XCTAssertEqual(finished, 0, "still writing the second camera's file")

    recordingManager.recordingDidFinish(url: second.startedURLs[0], error: nil)
    XCTAssertEqual(finished, 1)
  }

  func testAnInterruptionSuspendsBothCameras() {
    XCTAssertTrue(recordingManager.suspendRecording())
    XCTAssertEqual(first.stopCount, 1)
    XCTAssertEqual(second.stopCount, 1)
  }
}

class DeviceLossTests: XCTestCase {
  let suiteName = "OnCueTests.DeviceLoss"
  var defaults: UserDefaults!
  var recordingManager: RecordingManager!
  var recorder: FakeMovieRecorder!

  override func setUp() {
    defaults = UserDefaults(suiteName: suiteName)
    defaults.removePersistentDomain(forName: suiteName)
    defaults.set(true, forKey: "motionTriggerEnabled")
    defaults.set(false, forKey: "audioTriggerEnabled")
    recordingManager = RecordingManager(defaults: defaults)
    recordingManager.deviceAvailabilityChanged(camera: true, microphone: true)
    recorder = FakeMovieRecorder()
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
  }

  func testNothingCanArmBeforeDevicesAreKnown() {
    let fresh = RecordingManager(defaults: defaults)
    XCTAssertFalse(fresh.canArm())
  }

  func testLosingTheOnlyCameraForMotionDisarms() {
    recordingManager.startArming(countdown: 0)
    recordingManager.deviceAvailabilityChanged(camera: false, microphone: true)
    XCTAssertEqual(recordingManager.state(), .unarmed)
  }

  func testLosingTheCameraStaysArmedWhileSoundCanStillTrigger() {
    defaults.set(true, forKey: "audioTriggerEnabled")
    recordingManager.startArming(countdown: 0)
    recordingManager.deviceAvailabilityChanged(camera: false, microphone: true)
    XCTAssertEqual(recordingManager.state(), .armed)
    XCTAssertTrue(recordingManager.canArm())
  }

  func testLosingBothDevicesMidRecordingDisarmsAndEndsTheFile() {
    defaults.set(true, forKey: "audioTriggerEnabled")
    recordingManager.startArming(countdown: 0)
    recordingManager.startRecording(to: recorder)

    recordingManager.deviceAvailabilityChanged(camera: false, microphone: false)

    XCTAssertEqual(recordingManager.state(), .unarmed)
    XCTAssertEqual(recorder.stopCount, 1)
  }

  func testArmsItselfOnceAfterLaunchWhenAsked() {
    defaults.set(true, forKey: "armAtLogin")
    let manager = RecordingManager(defaults: defaults)
    var announced = 0
    manager.onArmedAtLaunch = { announced += 1 }

    manager.deviceAvailabilityChanged(camera: true, microphone: true)
    XCTAssertNotEqual(manager.state(), .unarmed)
    XCTAssertEqual(announced, 1)

    // A later device change doesn't arm it again after a disarm.
    manager.disarm()
    manager.deviceAvailabilityChanged(camera: true, microphone: true)
    XCTAssertEqual(manager.state(), .unarmed)
    XCTAssertEqual(announced, 1)
  }

  func testDoesNotArmItselfWhenNotAsked() {
    let manager = RecordingManager(defaults: defaults)
    manager.deviceAvailabilityChanged(camera: true, microphone: true)
    XCTAssertEqual(manager.state(), .unarmed)
  }

  func testTurningOffTheLastTriggerDisarms() {
    recordingManager.startArming(countdown: 0)
    defaults.set(false, forKey: "motionTriggerEnabled")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
    XCTAssertEqual(recordingManager.state(), .unarmed)
  }
}
