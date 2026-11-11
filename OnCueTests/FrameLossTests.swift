//
//  FrameLossTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/20/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import XCTest

class FrameLossTests: XCTestCase {
  private let frame = 1.0 / 30.0

  // MARK: - Counting where frames went

  func testCountsEachReasonSeparately() {
    var tally = FrameLoss.Tally()
    tally.record(.encoderBehind)
    tally.record(.encoderBehind)
    tally.record(.writerRefused)
    XCTAssertEqual(tally.counts[.encoderBehind], 2)
    XCTAssertEqual(tally.counts[.writerRefused], 1)
    XCTAssertNil(tally.counts[.encodeFailed])
    XCTAssertEqual(tally.total, 3)
  }

  func testAnUntouchedTallyHasNothingToSay() {
    XCTAssertEqual(FrameLoss.Tally().total, 0)
    XCTAssertEqual(FrameLoss.Tally().summary, "")
  }

  func testTheSummaryNamesOnlyWhatHappened() {
    var tally = FrameLoss.Tally()
    tally.record(.captureDropped)
    XCTAssertEqual(tally.summary, "captureDropped 1")
  }

  // MARK: - What the written frames say

  func testFramesArrivingOnTimeLeaveNoGap() {
    var gaps = FrameLoss.Gaps()
    for i in 0..<30 {
      gaps.wrote(at: Double(i) * frame, interval: frame)
    }
    XCTAssertEqual(gaps.written, 30)
    XCTAssertEqual(gaps.missing, 0)
    XCTAssertEqual(gaps.longest, 0)
  }

  /// Capture jitter shouldn't read as loss, which is what the half-interval slack is for.
  func testOrdinaryJitterIsNotAGap() {
    var gaps = FrameLoss.Gaps()
    gaps.wrote(at: 0, interval: frame)
    gaps.wrote(at: frame * 1.4, interval: frame)
    XCTAssertEqual(gaps.missing, 0)
  }

  func testAHoleIsMeasuredMinusTheFrameThatWouldHaveEndedIt() {
    var gaps = FrameLoss.Gaps()
    gaps.wrote(at: 0, interval: frame)
    gaps.wrote(at: 5, interval: frame)
    XCTAssertEqual(gaps.missing, 5 - frame, accuracy: 0.0001)
    XCTAssertEqual(gaps.longest, 5 - frame, accuracy: 0.0001)
  }

  func testTheLongestGapIsTheLongestNotTheLast() {
    var gaps = FrameLoss.Gaps()
    gaps.wrote(at: 0, interval: frame)
    gaps.wrote(at: 10, interval: frame)
    gaps.wrote(at: 12, interval: frame)
    XCTAssertEqual(gaps.longest, 10 - frame, accuracy: 0.0001)
    XCTAssertEqual(gaps.missing, 12 - 2 * frame, accuracy: 0.0001)
  }

  func testExpectedCountsTheFramesThatShouldHaveFilledTheGaps() {
    var gaps = FrameLoss.Gaps()
    gaps.wrote(at: 0, interval: frame)
    gaps.wrote(at: 1 + frame, interval: frame)
    // A second of hole is thirty frames that never arrived, plus the two that did.
    XCTAssertEqual(gaps.expected(interval: frame), 32)
  }

  // MARK: - Whether it's worth saying

  /// The shape of the file that started this spec: 451 frames where 1273 were due, with one
  /// 24 second hole.
  func testAFileWithALongHoleIsWorthSaying() {
    XCTAssertTrue(FrameLoss.worthSaying(longest: 24, missing: 30, written: 451, expected: 1273))
  }

  /// Shedding alternate frames leaves no gap worth the name, and would pass a gap test alone.
  func testEvenlySpreadLossIsWorthSayingToo() {
    XCTAssertTrue(FrameLoss.worthSaying(longest: 0.07, missing: 12, written: 450, expected: 900))
  }

  func testAHealthyRecordingSaysNothing() {
    // 29.8 fps over 26 seconds, which is what the good recordings measured.
    XCTAssertFalse(FrameLoss.worthSaying(longest: 0.2, missing: 0.1, written: 774, expected: 780))
  }

  func testAPerfectRecordingSaysNothing() {
    XCTAssertFalse(FrameLoss.worthSaying(longest: 0, missing: 0, written: 900, expected: 900))
  }

  func testAnEmptyRecordingSaysNothing() {
    XCTAssertFalse(FrameLoss.worthSaying(longest: 0, missing: 0, written: 0, expected: 0))
  }

  func testAGapExactlyAtTheThresholdCounts() {
    XCTAssertTrue(FrameLoss.worthSaying(longest: 1.0, missing: 1.0, written: 900, expected: 930))
  }

  // MARK: - What the name says

  func testTheNameCarriesTheTimeThatIsMissing() {
    XCTAssertEqual(FrameLoss.nameSuffix(longest: 24, missing: 27.6, written: 451, expected: 1273),
                   " - 28s missing")
  }

  func testAHealthyRecordingGetsNoSuffix() {
    XCTAssertNil(FrameLoss.nameSuffix(longest: 0.2, missing: 0.1, written: 774, expected: 780))
  }

  /// Rounding must never produce "0s missing" on a file that qualified.
  func testALossWorthSayingNeverRoundsToNothing() {
    XCTAssertEqual(FrameLoss.nameSuffix(longest: 1.2, missing: 1.2, written: 900, expected: 936),
                   " - 1s missing")
  }
}
