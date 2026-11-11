//
//  MotionHealthTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/21/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import XCTest

class MotionHealthTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 10_000)

  private func ago(_ seconds: TimeInterval) -> Date {
    now.addingTimeInterval(-seconds)
  }

  // MARK: - When detection counts as stopped

  func testStoppedAfterFiveSecondsWithoutAMeasurement() {
    XCTAssertTrue(MotionHealth.stopped(capturing: true, lastMeasured: ago(5), now: now))
    XCTAssertTrue(MotionHealth.stopped(capturing: true, lastMeasured: ago(30), now: now))
  }

  /// Under the window is a stall, not a failure. Capture warm-up alone can go most of a second.
  func testNotStoppedBeforeTheWindowIsUp() {
    XCTAssertFalse(MotionHealth.stopped(capturing: true, lastMeasured: ago(4.9), now: now))
    XCTAssertFalse(MotionHealth.stopped(capturing: true, lastMeasured: now, now: now))
  }

  /// The rule keys on measurements arriving, never on what they say. A camera pointed at a wall
  /// measures a level of zero and keeps reporting it, which is working, not stopped.
  func testACameraSeeingNothingIsStillMeasuring() {
    XCTAssertFalse(MotionHealth.stopped(capturing: true, lastMeasured: now, now: now))
  }

  /// Spec 0023 releases the camera when nothing needs it. Nothing is measuring, and nothing should
  /// be, so there is nothing to report.
  func testACameraReleasedOnPurposeIsNotStopped() {
    XCTAssertFalse(MotionHealth.stopped(capturing: false, lastMeasured: ago(600), now: now))
    XCTAssertFalse(MotionHealth.stopped(capturing: false, lastMeasured: nil, now: now))
  }

  /// Before the first measurement of a session there is nothing yet to be late.
  func testNothingMeasuredYetIsNotStopped() {
    XCTAssertFalse(MotionHealth.stopped(capturing: true, lastMeasured: nil, now: now))
  }

  // MARK: - What an outage leaves behind

  func testAFinishedOutageIsAGapFromTheLastMeasurementToTheFirstNewOne() {
    let last = ago(90)
    let outage = MotionHealth.outage(from: last, to: now)
    XCTAssertEqual(outage?.from, last)
    XCTAssertEqual(outage?.to, now)
  }

  /// A hiccup that never counted as stopped leaves nothing behind to report.
  func testAShortStallIsNotAnOutage() {
    XCTAssertNil(MotionHealth.outage(from: ago(4.9), to: now))
    XCTAssertNil(MotionHealth.outage(from: nil, to: now))
  }

  /// The threshold is the same on the way in and on the way out, so anything OnCue warned about
  /// leaves a gap and anything it stayed quiet about does not.
  func testTheOutageThresholdMatchesTheWarningThreshold() {
    let warned = MotionHealth.stopped(capturing: true, lastMeasured: ago(MotionHealth.stoppedAfter), now: now)
    let left = MotionHealth.outage(from: ago(MotionHealth.stoppedAfter), to: now)
    XCTAssertTrue(warned)
    XCTAssertNotNil(left)
  }
}
