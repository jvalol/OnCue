//
//  SampleRingTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/19/26.
//  Copyright © 2026 Jake Van Alstyne
//

import XCTest

class SampleRingTests: XCTestCase {
  /// One frame every half second for 10 seconds, a keyframe every second.
  func ring() -> SampleRing<Int> {
    var ring = SampleRing<Int>()
    for i in 0..<20 {
      let time = Double(i) * 0.5
      ring.append(.init(time: time, isKeyframe: i % 2 == 0, payload: i))
    }
    return ring
  }

  func testTrimKeepsTheWindowFromTheKeyframeThatDecodesIt() {
    var ring = ring()
    ring.trim(window: 5)
    XCTAssertEqual(ring.entries.first?.time, 4.0)
    XCTAssertEqual(ring.entries.last?.time, 9.5)
  }

  func testTrimKeepsEverythingWhenNothingIsOlderThanTheWindow() {
    var ring = ring()
    ring.trim(window: 30)
    XCTAssertEqual(ring.entries.count, 20)
  }

  /// The window is a property of the footage, so it has to be measured against the footage. A
  /// device that timestamps in its own timebase can sit far ahead of the host clock, and when it
  /// does, nothing in the ring is ever old enough to drop and the buffer grows until the app is
  /// killed. On a camera meant to run unattended that is a silent, permanent stop.
  func testTheRingIsTrimmedEvenWhenItsTimesRunAheadOfEverything() {
    var ring = SampleRing<Int>()
    // Ten minutes of footage, timestamped an hour ahead of any wall clock.
    for i in 0..<1200 {
      let time = 3600 + Double(i) * 0.5
      ring.append(.init(time: time, isKeyframe: i % 2 == 0, payload: i))
    }
    ring.trim(window: 5)
    XCTAssertLessThan(ring.entries.count, 20, "the ring kept footage far outside the window")
    XCTAssertEqual(ring.entries.last?.time, 3600 + 599.5)
  }

  /// A backstop for a device whose timestamps don't advance at all. Nothing else in the ring can
  /// bound it, since every sample looks like it arrived at the same moment.
  func testTheRingStopsGrowingEvenIfItsTimesNeverAdvance() {
    var ring = SampleRing<Int>()
    for i in 0..<(SampleRing<Int>.maximumEntries + 500) {
      ring.append(.init(time: 12.0, isKeyframe: i % 2 == 0, payload: i))
      ring.trim(window: 5)
    }
    XCTAssertLessThanOrEqual(ring.entries.count, SampleRing<Int>.maximumEntries)
    XCTAssertEqual(ring.entries.last?.payload, SampleRing<Int>.maximumEntries + 499,
                   "the newest sample is the one that must survive")
  }

  func testFootageStartsAtTheLatestKeyframeAtOrBeforeTheCutoff() {
    XCTAssertEqual(ring().startTime(notAfter: 4.5, after: nil), 4.0)
  }

  /// The pre-roll cutoff comes from the ring's own newest sample, so a device whose clock sits
  /// ahead of or behind the host's still gets a full window of footage rather than none.
  func testPreRollReachesBackAFullWindowWhateverAnOutsideClockSays() {
    let ring = ring()
    XCTAssertEqual(ring.cutoff(window: 5), 4.5)
    XCTAssertEqual(ring.startTime(notAfter: ring.cutoff(window: 5) ?? 0, after: nil), 4.0)
  }

  func testFootageStartsAtTheEarliestKeyframeWhenNoneIsOldEnough() {
    XCTAssertEqual(ring().startTime(notAfter: -1, after: nil), 0.0)
  }

  func testARestartDoesNotRepeatFootageAlreadyWritten() {
    XCTAssertEqual(ring().startTime(notAfter: 4.5, after: 7.2), 8.0)
    XCTAssertNil(ring().startTime(notAfter: 4.5, after: 9.5))
  }

  func testEntriesFromAStartTime() {
    XCTAssertEqual(ring().entries(from: 8.0).map { $0.payload }, [16, 17, 18, 19])
  }

  func testPreRollIsHeldToZeroThroughThirtySeconds() {
    XCTAssertEqual(PreRoll.clamp(-2), 0)
    XCTAssertEqual(PreRoll.clamp(5), 5)
    XCTAssertEqual(PreRoll.clamp(45), 30)
  }

  func testFootageIsDatedByWhenItWasCaptured() {
    let now = Date(timeIntervalSince1970: 10_000)
    XCTAssertEqual(PreRoll.date(ofSampleTime: 95, newestSampleTime: 100, now: now),
                   Date(timeIntervalSince1970: 9_995))
  }

  /// A device timestamping an hour ahead of the host clock used to name its recordings an hour in
  /// the future, because the sample time was compared against the host clock. Only the gap between
  /// two of the device's own times is used now, so the same five seconds of pre-roll dates the same
  /// whatever the device thinks the time is.
  func testTheNameIsUnaffectedByADeviceWhoseClockDisagrees() {
    let now = Date(timeIntervalSince1970: 10_000)
    let expected = Date(timeIntervalSince1970: 9_995)
    XCTAssertEqual(PreRoll.date(ofSampleTime: 95, newestSampleTime: 100, now: now), expected)
    XCTAssertEqual(PreRoll.date(ofSampleTime: 3_695, newestSampleTime: 3_700, now: now), expected,
                   "an hour ahead")
    XCTAssertEqual(PreRoll.date(ofSampleTime: -3_605, newestSampleTime: -3_600, now: now), expected,
                   "an hour behind")
  }

  /// A future-dated recording is what made this worth fixing rather than tidying: spec 0029's
  /// rolling window sorts on the date in the name, and one dated ahead never sorts as the oldest,
  /// so it is never deleted and the window quietly frees nothing.
  func testAFootageDateIsNeverAfterNow() {
    let now = Date(timeIntervalSince1970: 10_000)
    for (start, newest) in [(95.0, 100.0), (3_695.0, 3_700.0), (0.0, 30.0)] {
      XCTAssertLessThanOrEqual(PreRoll.date(ofSampleTime: start, newestSampleTime: newest, now: now), now)
    }
  }

  /// The newest sample is the one the gap is measured against, and the ring keeps them in order.
  func testTheRingKnowsItsNewestSampleTime() {
    XCTAssertEqual(ring().newest, 9.5)
    XCTAssertNil(SampleRing<Int>().newest)
  }
}
