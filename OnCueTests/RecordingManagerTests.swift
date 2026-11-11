//
//  RecordingManager_Tests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 2/2/20.
//  Copyright © 2020 Jake Van Alstyne. All rights reserved.
//

import XCTest

class RecordingManagerTests: XCTestCase {
  private let suite = "OnCueTests.RecordingManager"
  var recordingManager: RecordingManager!

  /// Its own defaults, so the app's real settings on this Mac (a schedule, for one) can't leak
  /// into what "Unarmed" says or whether the Mac is being kept awake.
  override func setUp() {
    UserDefaults().removePersistentDomain(forName: suite)
    let defaults = UserDefaults(suiteName: suite)!
    defaults.set(true, forKey: "motionTriggerEnabled")
    recordingManager = RecordingManager(defaults: defaults)
    // A camera, so the motion trigger can fire: otherwise the first defaults change auto-disarms.
    recordingManager.deviceAvailabilityChanged(camera: true, microphone: false)
  }

  override func tearDown() {
    recordingManager.disarm()
    recordingManager = nil
    UserDefaults().removePersistentDomain(forName: suite)
    super.tearDown()
  }

  // MARK: - What happened while armed (spec 0054)

  private var suiteDefaults: UserDefaults { UserDefaults(suiteName: suite)! }

  func testALongEmptyStretchIsRememberedOnDisarm() {
    var now = Date(timeIntervalSince1970: 1_790_000_000)
    recordingManager.clock = { now }
    recordingManager.startArming(countdown: 0)
    XCTAssertEqual(ArmedStretch.armedSince(in: suiteDefaults), now)
    now = now.addingTimeInterval(15 * 60)
    recordingManager.disarm()
    let stretch = ArmedStretch.read(from: suiteDefaults)
    XCTAssertEqual(stretch?.seconds, 15 * 60)
    XCTAssertNil(ArmedStretch.armedSince(in: suiteDefaults))
    XCTAssertEqual(recordingManager.whatHappened()?.stretch, stretch)
  }

  func testAShortEmptyStretchLeavesThePreviousOne() {
    var now = Date(timeIntervalSince1970: 1_790_000_000)
    recordingManager.clock = { now }
    let earlier = ArmedStretch(from: now.addingTimeInterval(-7200), to: now.addingTimeInterval(-3600))
    earlier.write(to: suiteDefaults)
    recordingManager.startArming(countdown: 0)
    now = now.addingTimeInterval(20)
    recordingManager.disarm()
    XCTAssertEqual(ArmedStretch.read(from: suiteDefaults), earlier)
  }

  func testANormalQuitWhileArmedClosesTheStretch() {
    var now = Date(timeIntervalSince1970: 1_790_000_000)
    recordingManager.clock = { now }
    recordingManager.startArming(countdown: 0)
    now = now.addingTimeInterval(3600)
    recordingManager.noteNormalQuit()
    XCTAssertEqual(ArmedStretch.read(from: suiteDefaults)?.seconds, 3600)
  }

  /// A crash ends the stretch at the last minute OnCue was seen, not at the relaunch.
  func testRecoveryClosesTheStretchTheCrashCutShort() {
    // The launch recovery runs once, at the first look, so this needs a manager of its own that
    // finds the record already there.
    let armed = Date(timeIntervalSince1970: 1_790_000_000)
    let lastSeen = armed.addingTimeInterval(45 * 60)
    let relaunch = lastSeen.addingTimeInterval(600)
    ArmedStretch.noteArmed(at: armed, in: suiteDefaults)
    ArmedRecord(lastSeen: lastSeen, bySchedule: false).write(to: suiteDefaults)
    let relaunched = RecordingManager(defaults: suiteDefaults)
    relaunched.clock = { relaunch }
    relaunched.deviceAvailabilityChanged(camera: true, microphone: false)
    XCTAssertEqual(ArmedStretch.read(from: suiteDefaults), ArmedStretch(from: armed, to: lastSeen))
    // Re-armed by the recovery, so a new stretch is open from the relaunch.
    XCTAssertEqual(ArmedStretch.armedSince(in: suiteDefaults), relaunch)
    relaunched.disarm()
  }

  func testInitializesAsUnarmed() {
    XCTAssertFalse(recordingManager.isArmed())
    XCTAssertEqual(recordingManager.armedStateDescription, "Unarmed")
    XCTAssertEqual(recordingManager.armedStateColor, .labelColor)
  }

  func testArmingCountsDownAndArms() {
    recordingManager.startArming(countdown: 5)

    XCTAssertEqual(recordingManager.armedStateColor, .systemOrange)
    XCTAssertEqual(recordingManager.armedStateDescription, "Arming… 5")
    for expected in ["Arming… 4", "Arming… 3", "Arming… 2", "Arming… 1", "Armed"] {
      waitForDescription(expected)
    }
    XCTAssertEqual(recordingManager.armedStateColor, .systemRed)
    XCTAssertTrue(recordingManager.isArmed())
  }

  func testArmingCanBeDisarmed() {
    recordingManager.startArming(countdown: 5)

    XCTAssertEqual(recordingManager.armedStateDescription, "Arming… 5")
    waitForDescription("Arming… 4")

    recordingManager.disarm()

    XCTAssertFalse(recordingManager.isArmed())
    XCTAssertEqual(recordingManager.armedStateColor, .labelColor)
    XCTAssertEqual(recordingManager.armedStateDescription, "Unarmed")
  }

  func testDisarmingDuringCountdownStaysUnarmed() {
    recordingManager.startArming(countdown: 1)
    recordingManager.disarm()

    RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.5))

    XCTAssertFalse(recordingManager.isArmed())
    XCTAssertEqual(recordingManager.armedStateDescription, "Unarmed")
  }

  func testKeepsMacAwakeFromArmingUntilDisarmed() {
    XCTAssertFalse(recordingManager.isKeepingAwake)

    recordingManager.startArming(countdown: 1)
    XCTAssertTrue(recordingManager.isKeepingAwake)

    waitForDescription("Armed")
    XCTAssertTrue(recordingManager.isKeepingAwake)

    recordingManager.disarm()
    XCTAssertFalse(recordingManager.isKeepingAwake)
  }

  func testArmingNeedsATriggerThatCanFire() {
    XCTAssertTrue(RecordingManager.armingAllowed(state: .unarmed, motionEnabled: true, cameraAvailable: true, audioEnabled: false, audioAvailable: false))
    XCTAssertTrue(RecordingManager.armingAllowed(state: .unarmed, motionEnabled: false, cameraAvailable: true, audioEnabled: true, audioAvailable: true))
    XCTAssertFalse(RecordingManager.armingAllowed(state: .unarmed, motionEnabled: false, cameraAvailable: true, audioEnabled: false, audioAvailable: true))
    XCTAssertFalse(RecordingManager.armingAllowed(state: .unarmed, motionEnabled: false, cameraAvailable: true, audioEnabled: true, audioAvailable: false))
  }

  func testDisarmingIsAlwaysAllowed() {
    for state in [RecordingManager.ArmState.arming, .armed, .recording] {
      XCTAssertTrue(RecordingManager.armingAllowed(state: state, motionEnabled: false, cameraAvailable: true, audioEnabled: false, audioAvailable: false))
    }
  }

  func testAutoDisarmsWhenNoTriggerCanFire() {
    for state in [RecordingManager.ArmState.arming, .armed, .recording] {
      XCTAssertTrue(RecordingManager.shouldAutoDisarm(state: state, motionEnabled: false, cameraAvailable: true, audioEnabled: false, audioAvailable: true))
      XCTAssertTrue(RecordingManager.shouldAutoDisarm(state: state, motionEnabled: false, cameraAvailable: true, audioEnabled: true, audioAvailable: false))
      XCTAssertFalse(RecordingManager.shouldAutoDisarm(state: state, motionEnabled: true, cameraAvailable: true, audioEnabled: false, audioAvailable: false))
      XCTAssertFalse(RecordingManager.shouldAutoDisarm(state: state, motionEnabled: false, cameraAvailable: true, audioEnabled: true, audioAvailable: true))
    }
    XCTAssertFalse(RecordingManager.shouldAutoDisarm(state: .unarmed, motionEnabled: false, cameraAvailable: true, audioEnabled: false, audioAvailable: false))
  }

  func testMotionNeedsACameraToCount() {
    XCTAssertFalse(RecordingManager.armingAllowed(state: .unarmed, motionEnabled: true, cameraAvailable: false, audioEnabled: false, audioAvailable: true))
    XCTAssertTrue(RecordingManager.armingAllowed(state: .unarmed, motionEnabled: true, cameraAvailable: false, audioEnabled: true, audioAvailable: true))
    XCTAssertTrue(RecordingManager.shouldAutoDisarm(state: .armed, motionEnabled: true, cameraAvailable: false, audioEnabled: false, audioAvailable: true))
    XCTAssertFalse(RecordingManager.shouldAutoDisarm(state: .armed, motionEnabled: true, cameraAvailable: false, audioEnabled: true, audioAvailable: true))
    XCTAssertTrue(RecordingManager.shouldAutoDisarm(state: .recording, motionEnabled: true, cameraAvailable: false, audioEnabled: true, audioAvailable: false))
  }

  // MARK: - Motion detection stopping (spec 0030)

  /// A camera that is present but measuring nothing can't fire any more than a missing one can,
  /// and arming while nothing can fire is the lie this exists to stop.
  func testArmIsRefusedWhileDetectionHasStopped() {
    XCTAssertFalse(RecordingManager.armingAllowed(state: .unarmed, motionEnabled: true, cameraAvailable: true,
                                                  audioEnabled: false, audioAvailable: false, motionWorking: false))
    XCTAssertTrue(RecordingManager.armingAllowed(state: .unarmed, motionEnabled: true, cameraAvailable: true,
                                                 audioEnabled: false, audioAvailable: false, motionWorking: true))
  }

  /// Sound is untouched by any of this, so it still lets you arm.
  func testSoundStillArmsWhileDetectionHasStopped() {
    XCTAssertTrue(RecordingManager.armingAllowed(state: .unarmed, motionEnabled: true, cameraAvailable: true,
                                                 audioEnabled: true, audioAvailable: true, motionWorking: false))
  }

  /// Deliberately the opposite of refusing to Arm. Refusing happens while someone is at the
  /// popover and can act; disarming happens after they have walked away and nobody can undo it.
  func testAnArmedOnCueStaysArmedWhileDetectionHasStopped() {
    recordingManager.startArming(countdown: 0)
    recordingManager.motionDetectionChanged(stopped: true)
    XCTAssertNotEqual(recordingManager.state(), .unarmed)
    XCTAssertTrue(recordingManager.motionDetectionStopped)
  }

  func testDetectionComingBackClearsTheWarning() {
    recordingManager.motionDetectionChanged(stopped: true)
    recordingManager.motionDetectionChanged(stopped: false)
    XCTAssertFalse(recordingManager.motionDetectionStopped)
  }

  /// The outage leaves the same hole a sleep gap does, and it stays until disarm.
  func testAnOutageWhileArmedLeavesAGap() {
    let from = Date(timeIntervalSince1970: 1_000), to = Date(timeIntervalSince1970: 1_120)
    recordingManager.startArming(countdown: 0)
    recordingManager.noteNotWatching(from: from, to: to)
    XCTAssertEqual(recordingManager.notWatchingFrom, from)
    XCTAssertEqual(recordingManager.notWatchingUntil, to)
  }

  /// Unarmed, OnCue wasn't meant to be watching, so nothing was missed and nothing is claimed.
  func testAnOutageWhileUnarmedLeavesNothing() {
    recordingManager.noteNotWatching(from: Date(timeIntervalSince1970: 1_000),
                                     to: Date(timeIntervalSince1970: 1_120))
    XCTAssertNil(recordingManager.notWatchingUntil)
  }

  func testSleepingWhileArmedRecordsTheGap() {
    let slept = Date(timeIntervalSince1970: 1_000), woke = Date(timeIntervalSince1970: 2_800)
    recordingManager.startArming(countdown: 0)

    recordingManager.systemWillSleep(at: slept)
    recordingManager.systemDidWake(at: woke)

    XCTAssertEqual(recordingManager.notWatchingFrom, slept)
    XCTAssertEqual(recordingManager.notWatchingUntil, woke)
  }

  func testSleepingWhileUnarmedRecordsNothing() {
    recordingManager.systemWillSleep(at: Date(timeIntervalSince1970: 1_000))
    recordingManager.systemDidWake(at: Date(timeIntervalSince1970: 2_000))
    XCTAssertNil(recordingManager.notWatchingUntil)
  }

  func testDisarmingClearsTheGap() {
    recordingManager.startArming(countdown: 0)
    recordingManager.systemWillSleep(at: Date(timeIntervalSince1970: 1_000))
    recordingManager.systemDidWake(at: Date(timeIntervalSince1970: 2_000))

    recordingManager.disarm()

    XCTAssertNil(recordingManager.notWatchingFrom)
    XCTAssertNil(recordingManager.notWatchingUntil)
  }

  func testArmsAtLaunchOnlyWhenAskedAndSomethingCanFire() {
    XCTAssertTrue(RecordingManager.shouldArmAtLaunch(enabled: true, state: .unarmed, motionEnabled: true,
                                                     cameraAvailable: true, audioEnabled: false, audioAvailable: false))
    XCTAssertFalse(RecordingManager.shouldArmAtLaunch(enabled: false, state: .unarmed, motionEnabled: true,
                                                      cameraAvailable: true, audioEnabled: false, audioAvailable: false))
    XCTAssertFalse(RecordingManager.shouldArmAtLaunch(enabled: true, state: .unarmed, motionEnabled: true,
                                                      cameraAvailable: false, audioEnabled: false, audioAvailable: false))
    XCTAssertFalse(RecordingManager.shouldArmAtLaunch(enabled: true, state: .unarmed, motionEnabled: false,
                                                      cameraAvailable: true, audioEnabled: false, audioAvailable: true))
  }

  func testDoesNotArmAtLaunchWhenAlreadyArmed() {
    for state in [RecordingManager.ArmState.arming, .armed, .recording] {
      XCTAssertFalse(RecordingManager.shouldArmAtLaunch(enabled: true, state: state, motionEnabled: true,
                                                        cameraAvailable: true, audioEnabled: true, audioAvailable: true))
    }
  }

  // The countdown runs on a main run loop Timer, so spin the run loop while polling.
  private func waitForDescription(_ expected: String, timeout: TimeInterval = 2, file: StaticString = #filePath, line: UInt = #line) {
    let deadline = Date(timeIntervalSinceNow: timeout)
    while recordingManager.armedStateDescription != expected && Date() < deadline {
      RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    }
    XCTAssertEqual(recordingManager.armedStateDescription, expected, file: file, line: line)
  }
}
