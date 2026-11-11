//
//  SleepRiskTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/19/26.
//  Copyright © 2026 Jake Van Alstyne
//

import XCTest

class SleepRiskTests: XCTestCase {
  func testALaptopOnBatteryOrWithoutADisplayWouldSleep() {
    XCTAssertTrue(SleepRisk.lidWouldStopWatching(hasLid: true, onExternalPower: false, hasExternalDisplay: true))
    XCTAssertTrue(SleepRisk.lidWouldStopWatching(hasLid: true, onExternalPower: true, hasExternalDisplay: false))
    XCTAssertTrue(SleepRisk.lidWouldStopWatching(hasLid: true, onExternalPower: false, hasExternalDisplay: false))
  }

  func testClamshellModeStaysAwake() {
    XCTAssertFalse(SleepRisk.lidWouldStopWatching(hasLid: true, onExternalPower: true, hasExternalDisplay: true))
  }

  func testADesktopHasNoLidToClose() {
    XCTAssertFalse(SleepRisk.lidWouldStopWatching(hasLid: false, onExternalPower: false, hasExternalDisplay: false))
  }

  func testAGapShowsOnlyWhileArmed() {
    XCTAssertEqual(PopoverNotice.notice(armed: false, lidRisk: false, gapStart: Date(), gapEnd: Date()), .none)
  }

  func testWarnsWithTheRiskArmedOrNot() {
    XCTAssertEqual(PopoverNotice.notice(armed: true, lidRisk: true, gapStart: nil, gapEnd: nil), .lidWouldStopWatching)
    XCTAssertEqual(PopoverNotice.notice(armed: false, lidRisk: true, gapStart: nil, gapEnd: nil), .lidWouldStopWatching)
    XCTAssertEqual(PopoverNotice.notice(armed: true, lidRisk: false, gapStart: nil, gapEnd: nil), .none)
    XCTAssertEqual(PopoverNotice.notice(armed: false, lidRisk: false, gapStart: nil, gapEnd: nil), .none)
  }

  func testAGapOutranksTheWarning() {
    let start = Date(timeIntervalSince1970: 1_000), end = Date(timeIntervalSince1970: 2_000)
    XCTAssertEqual(PopoverNotice.notice(armed: true, lidRisk: true, gapStart: start, gapEnd: end), .wasNotWatching(from: start, to: end))
  }

  // MARK: - Motion detection stopped (spec 0030)

  /// The only live problem in this enum, and it outranks every one of the others, which are all
  /// news about something that already finished.
  func testDetectionStoppedOutranksEverythingElse() {
    let start = Date(timeIntervalSince1970: 1_000), end = Date(timeIntervalSince1970: 2_000)
    XCTAssertEqual(PopoverNotice.notice(armed: true, lidRisk: true, gapStart: start, gapEnd: end,
                                        failure: .diskFull, failureCount: 3, failedAt: end,
                                        deletedCount: 2, deletedAt: end, motionStopped: true),
                   .motionDetectionStopped(soundStillWatching: false))
  }

  /// Shown armed or not, the way the lid warning is: it is the reason Arm is unavailable, so it
  /// has to be readable before pressing it.
  func testDetectionStoppedShowsArmedOrNot() {
    XCTAssertEqual(PopoverNotice.notice(armed: false, lidRisk: false, gapStart: nil, gapEnd: nil,
                                        motionStopped: true),
                   .motionDetectionStopped(soundStillWatching: false))
    XCTAssertEqual(PopoverNotice.notice(armed: true, lidRisk: false, gapStart: nil, gapEnd: nil,
                                        motionStopped: true),
                   .motionDetectionStopped(soundStillWatching: false))
  }

  /// Sound only counts as covering for motion when it is actually watching, which takes the arm
  /// state as well as the trigger and its mic. Unarmed nothing is watching, and that is exactly
  /// when someone is working out whether they are covered.
  func testSoundOnlyCoversForMotionWhileArmed() {
    XCTAssertEqual(PopoverNotice.notice(armed: true, lidRisk: false, gapStart: nil, gapEnd: nil,
                                        motionStopped: true, soundCanWatch: true),
                   .motionDetectionStopped(soundStillWatching: true))
    XCTAssertEqual(PopoverNotice.notice(armed: false, lidRisk: false, gapStart: nil, gapEnd: nil,
                                        motionStopped: true, soundCanWatch: true),
                   .motionDetectionStopped(soundStillWatching: false))
    XCTAssertEqual(PopoverNotice.notice(armed: true, lidRisk: false, gapStart: nil, gapEnd: nil,
                                        motionStopped: true, soundCanWatch: false),
                   .motionDetectionStopped(soundStillWatching: false))
  }

  /// Once it recovers the line goes back to whatever else is true, including the gap it left.
  func testTheGapIsWhatRemainsAfterDetectionRecovers() {
    let start = Date(timeIntervalSince1970: 1_000), end = Date(timeIntervalSince1970: 2_000)
    XCTAssertEqual(PopoverNotice.notice(armed: true, lidRisk: false, gapStart: start, gapEnd: end,
                                        motionStopped: false),
                   .wasNotWatching(from: start, to: end))
  }

  // MARK: - A failed recording (spec 0027)

  private let earlier = Date(timeIntervalSince1970: 1_000)
  private let later = Date(timeIntervalSince1970: 9_000)

  func testAFailedRecordingOutranksTheLidWarning() {
    XCTAssertEqual(PopoverNotice.notice(armed: true, lidRisk: true, gapStart: nil, gapEnd: nil,
                                        failure: .diskFull, failureCount: 1, failedAt: earlier),
                   .recordingFailed(.diskFull, count: 1, at: earlier))
  }

  /// A gap and a failure are the same class of bad news, so the newer one wins rather than either
  /// having a fixed rank.
  func testTheMoreRecentOfAGapAndAFailureWins() {
    XCTAssertEqual(PopoverNotice.notice(armed: true, lidRisk: false, gapStart: earlier, gapEnd: earlier,
                                        failure: .diskFull, failureCount: 1, failedAt: later),
                   .recordingFailed(.diskFull, count: 1, at: later))
    XCTAssertEqual(PopoverNotice.notice(armed: true, lidRisk: false, gapStart: earlier, gapEnd: later,
                                        failure: .diskFull, failureCount: 1, failedAt: earlier),
                   .wasNotWatching(from: earlier, to: later))
  }

  func testNoFailureLeavesTheOtherNoticesAlone() {
    XCTAssertEqual(PopoverNotice.notice(armed: true, lidRisk: true, gapStart: nil, gapEnd: nil,
                                        failure: nil, failureCount: 0, failedAt: nil),
                   .lidWouldStopWatching)
    XCTAssertEqual(PopoverNotice.notice(armed: false, lidRisk: false, gapStart: nil, gapEnd: nil,
                                        failure: nil, failureCount: 0, failedAt: nil), .none)
  }

  /// Both cameras failing is one failure to report, not two, so the count is what says how many
  /// recordings were lost rather than how many files were attempted.
  func testTheCountCarriesThrough() {
    XCTAssertEqual(PopoverNotice.notice(armed: true, lidRisk: false, gapStart: nil, gapEnd: nil,
                                        failure: .destinationMissing, failureCount: 7, failedAt: later),
                   .recordingFailed(.destinationMissing, count: 7, at: later))
  }

  func testAFailureWithoutACountSaysNothing() {
    XCTAssertEqual(PopoverNotice.notice(armed: true, lidRisk: false, gapStart: nil, gapEnd: nil,
                                        failure: .diskFull, failureCount: 0, failedAt: later), .none)
  }

  // MARK: - Fresh start (spec 0037)

  func testAFreshStartShowsArmedOrNot() {
    XCTAssertEqual(PopoverNotice.notice(armed: false, lidRisk: false, gapStart: nil, gapEnd: nil,
                                        freshStart: true), .freshStart)
    XCTAssertEqual(PopoverNotice.notice(armed: true, lidRisk: false, gapStart: nil, gapEnd: nil,
                                        freshStart: true), .freshStart)
  }

  /// On a first launch the reset is the likeliest thing wrong with this Mac's setup, so it comes
  /// before the standing lid warning.
  func testAFreshStartOutranksTheLidWarning() {
    XCTAssertEqual(PopoverNotice.notice(armed: false, lidRisk: true, gapStart: nil, gapEnd: nil,
                                        freshStart: true), .freshStart)
  }

  /// Anything that cost footage, or is costing it now, comes first: those are why the notice line
  /// exists, and a fresh start is only advice.
  func testAnythingThatWentWrongOutranksAFreshStart() {
    XCTAssertEqual(PopoverNotice.notice(armed: true, lidRisk: false, gapStart: earlier, gapEnd: later,
                                        freshStart: true), .wasNotWatching(from: earlier, to: later))
    XCTAssertEqual(PopoverNotice.notice(armed: true, lidRisk: false, gapStart: nil, gapEnd: nil,
                                        failure: .diskFull, failureCount: 1, failedAt: later,
                                        freshStart: true), .recordingFailed(.diskFull, count: 1, at: later))
    XCTAssertEqual(PopoverNotice.notice(armed: true, lidRisk: false, gapStart: nil, gapEnd: nil,
                                        deletedCount: 1, deletedAt: later,
                                        freshStart: true), .recordingsDeleted(count: 1, at: later))
    XCTAssertEqual(PopoverNotice.notice(armed: true, lidRisk: false, gapStart: nil, gapEnd: nil,
                                        motionStopped: true, freshStart: true),
                   .motionDetectionStopped(soundStillWatching: false))
  }

  func testNoFreshStartLeavesTheOtherNoticesAlone() {
    XCTAssertEqual(PopoverNotice.notice(armed: false, lidRisk: true, gapStart: nil, gapEnd: nil,
                                        freshStart: false), .lidWouldStopWatching)
    XCTAssertEqual(PopoverNotice.notice(armed: false, lidRisk: false, gapStart: nil, gapEnd: nil,
                                        freshStart: false), .none)
  }

  // MARK: - An unexpected quit (spec 0045)

  func testAnUnexpectedQuitShowsArmedOrNot() {
    let at = Date(timeIntervalSince1970: 1_000), until = Date(timeIntervalSince1970: 2_000)
    XCTAssertEqual(PopoverNotice.notice(armed: false, lidRisk: true, gapStart: nil, gapEnd: nil, quitAt: at, quitUntil: until),
                   .quitUnexpectedly(at: at, until: until))
    XCTAssertEqual(PopoverNotice.notice(armed: true, lidRisk: false, gapStart: nil, gapEnd: nil, quitAt: at, quitUntil: until),
                   .quitUnexpectedly(at: at, until: until))
  }

  func testAnUnexpectedQuitRanksByRecencyWithTheOtherNews() {
    let at = Date(timeIntervalSince1970: 1_000), until = Date(timeIntervalSince1970: 2_000)
    let later = Date(timeIntervalSince1970: 3_000), earlier = Date(timeIntervalSince1970: 500)
    XCTAssertEqual(PopoverNotice.notice(armed: true, lidRisk: false, gapStart: nil, gapEnd: nil,
                                        failure: .diskFull, failureCount: 1, failedAt: later, quitAt: at, quitUntil: until),
                   .recordingFailed(.diskFull, count: 1, at: later), "the newer failure wins")
    XCTAssertEqual(PopoverNotice.notice(armed: true, lidRisk: false, gapStart: nil, gapEnd: nil,
                                        failure: .diskFull, failureCount: 1, failedAt: earlier, quitAt: at, quitUntil: until),
                   .quitUnexpectedly(at: at, until: until), "the newer quit wins")
    XCTAssertEqual(PopoverNotice.notice(armed: true, lidRisk: false, gapStart: nil, gapEnd: nil,
                                        motionStopped: true, quitAt: at, quitUntil: until),
                   .motionDetectionStopped(soundStillWatching: false), "a live problem still outranks it")
  }

  // MARK: - A schedule that can't survive a restart (spec 0051)

  func testTheScheduleRiskShowsArmedOrNotAndBeatsTheLid() {
    XCTAssertEqual(PopoverNotice.notice(armed: false, lidRisk: true, gapStart: nil, gapEnd: nil, scheduleAtRisk: true),
                   .scheduleCannotSurviveRestart, "the one fixed in Settings wins")
    XCTAssertEqual(PopoverNotice.notice(armed: true, lidRisk: false, gapStart: nil, gapEnd: nil, scheduleAtRisk: true),
                   .scheduleCannotSurviveRestart)
    XCTAssertEqual(PopoverNotice.notice(armed: false, lidRisk: true, gapStart: nil, gapEnd: nil, scheduleAtRisk: false),
                   .lidWouldStopWatching)
  }

  func testAnythingThatHappenedOrAFreshStartOutranksTheScheduleRisk() {
    let at = Date(timeIntervalSince1970: 1_000)
    XCTAssertEqual(PopoverNotice.notice(armed: true, lidRisk: false, gapStart: nil, gapEnd: nil,
                                        failure: .diskFull, failureCount: 1, failedAt: at, scheduleAtRisk: true),
                   .recordingFailed(.diskFull, count: 1, at: at))
    XCTAssertEqual(PopoverNotice.notice(armed: false, lidRisk: false, gapStart: nil, gapEnd: nil,
                                        freshStart: true, scheduleAtRisk: true),
                   .freshStart)
  }

  // MARK: - After an update (spec 0058)

  func testAnUpdateShowsBelowWhatHappenedAndAboveTheRisks() {
    let at = Date(timeIntervalSince1970: 1_000)
    XCTAssertEqual(PopoverNotice.notice(armed: false, lidRisk: true, gapStart: nil, gapEnd: nil,
                                        scheduleAtRisk: true, update: .to("4.20")),
                   .updated(.to("4.20")))
    XCTAssertEqual(PopoverNotice.notice(armed: false, lidRisk: false, gapStart: nil, gapEnd: nil,
                                        freshStart: true, update: .fromOlder),
                   .freshStart)
    XCTAssertEqual(PopoverNotice.notice(armed: true, lidRisk: false, gapStart: nil, gapEnd: nil,
                                        failure: .diskFull, failureCount: 1, failedAt: at, update: .fromOlder),
                   .recordingFailed(.diskFull, count: 1, at: at))
  }
}
