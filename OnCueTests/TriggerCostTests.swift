//
//  TriggerCostTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/21/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import XCTest

class TriggerCostTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_790_000_000)
  /// What the encoder is pinned to, so a megabyte is about a second.
  private let bitrate = 8_000_000.0

  private func recording(secondsAgo: TimeInterval, lengthSeconds: Double) -> DiskBudget.Recording {
    DiskBudget.Recording(url: URL(fileURLWithPath: "/tmp/\(secondsAgo)-\(lengthSeconds).mov"),
                         started: now.addingTimeInterval(-secondsAgo),
                         bytes: Int64(lengthSeconds * bitrate / 8))
  }

  private func many(_ count: Int, lengthSeconds: Double, secondsAgo: TimeInterval = 3600) -> [DiskBudget.Recording] {
    (0..<count).map { recording(secondsAgo: secondsAgo + Double($0), lengthSeconds: lengthSeconds) }
  }

  /// A still beside every recording (spec 0053) is OnCue's own file by name and must not count.
  func testStillsBesideRecordingsAreNotRecordings() {
    let movies = many(4, lengthSeconds: 30)
    let stills = movies.map { DiskBudget.Recording(url: $0.url.deletingPathExtension().appendingPathExtension("jpg"),
                                                   started: $0.started, bytes: 300_000) }
    XCTAssertEqual(summary(movies + stills)?.count, summary(movies)?.count)
    XCTAssertEqual(summary(movies + stills)?.typicalSeconds, summary(movies)?.typicalSeconds)
  }

  private func summary(_ recordings: [DiskBudget.Recording], preRoll: Double = 5, timeout: Int = 5) -> TriggerCost.Summary? {
    TriggerCost.summary(recordings: recordings, now: now, bitsPerSecond: bitrate,
                        preRoll: preRoll, timeout: timeout)
  }

  // MARK: - Saying nothing rather than saying something untrue

  /// A fresh install has nothing to describe, and saying so would be inventing a number.
  func testNothingToSayWithNoRecordings() {
    XCTAssertNil(summary([]))
  }

  /// The floor is about whether a typical means anything, not about whether the answer flatters
  /// the setting. A quiet day is silent, and that silence is not approval.
  func testNothingToSayBelowTheFloor() {
    XCTAssertNil(summary(many(TriggerCost.enoughToDescribe - 1, lengthSeconds: 11)))
  }

  func testSaysSomethingAtTheFloor() {
    XCTAssertEqual(summary(many(TriggerCost.enoughToDescribe, lengthSeconds: 11))?.count,
                   TriggerCost.enoughToDescribe)
  }

  /// A busy day and a quiet one are counted the same way. Nothing here decides that a number is
  /// too high: the reader does, knowing the room.
  func testABusyDayIsReportedNotJudged() {
    XCTAssertEqual(summary(many(297, lengthSeconds: 11))?.count, 297)
  }

  // MARK: - The window

  func testOnlyTheLastDayCounts() {
    let old = many(50, lengthSeconds: 11, secondsAgo: TriggerCost.window + 60)
    XCTAssertNil(summary(old), "recordings older than the window aren't in it")

    let mixed = old + many(12, lengthSeconds: 11, secondsAgo: 600)
    XCTAssertEqual(summary(mixed)?.count, 12)
  }

  /// A file dated in the future is not in the last 24 hours. Clock skew can produce one, and it
  /// would otherwise be counted and drag the typical around (see the clock skew note in memory).
  func testAFutureDatedRecordingIsNotCounted() {
    let future = [recording(secondsAgo: -600, lengthSeconds: 900)]
    XCTAssertNil(summary(future + many(9, lengthSeconds: 11)))
  }

  // MARK: - What it reports

  /// A median, not a mean: one long event shouldn't move the number away from what the folder is
  /// actually full of.
  func testTheTypicalIsTheMiddleRecordingNotTheAverage() {
    let brief = many(10, lengthSeconds: 11)
    let oneLongOne = [recording(secondsAgo: 100, lengthSeconds: 3600)]
    let reported = summary(brief + oneLongOne)
    XCTAssertEqual(reported?.typicalSeconds ?? 0, 11, accuracy: 0.01)
  }

  func testLengthComesFromSizeAtTheFixedBitrate() {
    // A megabyte at 8 Mbit/s is one second.
    XCTAssertEqual(TriggerCost.seconds(bytes: 1_000_000, bitsPerSecond: bitrate), 1, accuracy: 0.001)
    XCTAssertEqual(TriggerCost.seconds(bytes: 0, bitsPerSecond: bitrate), 0)
    XCTAssertEqual(TriggerCost.seconds(bytes: 1_000_000, bitsPerSecond: 0), 0, "no divide by zero")
  }

  /// The other end of the ruler, so the comparison lands without OnCue drawing it. Both numbers
  /// are the user's own settings.
  func testTheShortestPossibleComesFromThePreRollAndTheTimeout() {
    XCTAssertEqual(TriggerCost.shortestPossibleSeconds(preRoll: 5, timeout: 5), 10)
    XCTAssertEqual(TriggerCost.shortestPossibleSeconds(preRoll: 30, timeout: 600), 630)
    XCTAssertEqual(TriggerCost.shortestPossibleSeconds(preRoll: 0, timeout: 0), 0)
    XCTAssertEqual(TriggerCost.shortestPossibleSeconds(preRoll: -5, timeout: -5), 0, "never negative")
  }

  /// The case that prompted the spec: recordings sitting barely above the floor, which is what a
  /// threshold catching noise looks like. OnCue reports both numbers and says nothing about them.
  func testRecordingsAtTheFloorAreReportedAlongsideIt() {
    let reported = summary(many(147, lengthSeconds: 11))
    XCTAssertEqual(reported?.count, 147)
    XCTAssertEqual(reported?.typicalSeconds ?? 0, 11, accuracy: 0.01)
    XCTAssertEqual(reported?.shortestPossibleSeconds, 10)
  }

  // MARK: - The line (reworded 2026-09-23)

  func testALineNearTheFloorSaysSo() {
    let summary = TriggerCost.Summary(count: 330, typicalSeconds: 12, shortestPossibleSeconds: 10)
    XCTAssertTrue(summary.text.hasPrefix("330 recordings in the last day, most barely longer than the 10s minimum."), summary.text)
  }

  func testALineWellPastTheFloorGivesBothNumbers() {
    let summary = TriggerCost.Summary(count: 12, typicalSeconds: 45, shortestPossibleSeconds: 10)
    XCTAssertTrue(summary.text.hasPrefix("12 recordings in the last day, typically 45s. OnCue can't make one shorter than 10s."), summary.text)
  }

  func testTheFloorFactorIsTheBoundary() {
    let just = TriggerCost.Summary(count: 5, typicalSeconds: 14.9, shortestPossibleSeconds: 10)
    XCTAssertTrue(just.text.contains("barely"), just.text)
    let past = TriggerCost.Summary(count: 5, typicalSeconds: 15, shortestPossibleSeconds: 10)
    XCTAssertFalse(past.text.contains("barely"), past.text)
  }
}
