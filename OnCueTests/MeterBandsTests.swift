//
//  MeterBandsTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/20/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import XCTest

class MeterBandsTests: XCTestCase {
  /// What an NSLevelIndicator would draw at this level, given the edges for a threshold.
  private func colour(level: Double, threshold: Double) -> String {
    let edges = MeterBands.edges(threshold: threshold)
    if level >= edges.critical { return "red" }
    if level >= edges.warning { return "yellow" }
    return "green"
  }

  func testGreenWhileNothingWouldTrigger() {
    XCTAssertEqual(colour(level: 10, threshold: 50), "green")
    XCTAssertEqual(colour(level: 37, threshold: 50), "green")
  }

  func testYellowApproachingTheThreshold() {
    XCTAssertEqual(colour(level: 38, threshold: 50), "yellow")
    XCTAssertEqual(colour(level: 49, threshold: 50), "yellow")
  }

  func testRedAtTheThreshold() {
    XCTAssertEqual(colour(level: 50, threshold: 50), "red")
    XCTAssertEqual(colour(level: 80, threshold: 50), "red")
  }

  /// The band moves with the setting, which is the whole point: the same level reads differently
  /// depending on what it's being compared against.
  func testTheSameLevelReadsDifferentlyAgainstDifferentThresholds() {
    XCTAssertEqual(colour(level: 60, threshold: 25), "red")
    XCTAssertEqual(colour(level: 60, threshold: 70), "yellow")
    XCTAssertEqual(colour(level: 60, threshold: 100), "green")
  }

  func testYellowIsTheTopQuarterBelowTheThreshold() {
    let edges = MeterBands.edges(threshold: 80)
    XCTAssertEqual(edges.warning, 60, accuracy: 0.0001)
    XCTAssertEqual(edges.critical, 80, accuracy: 0.0001)
  }

  /// A threshold at the top means nothing can trigger, so nothing is red.
  func testTheHighestThresholdLeavesTheMeterGreen() {
    XCTAssertEqual(colour(level: 99, threshold: 100), "yellow")
    XCTAssertEqual(colour(level: 75, threshold: 100), "yellow")
    XCTAssertEqual(colour(level: 10, threshold: 100), "green")
  }

  /// A threshold of zero means anything triggers, so everything is red.
  func testTheLowestThresholdLeavesTheMeterRed() {
    XCTAssertEqual(colour(level: 0, threshold: 0), "red")
    XCTAssertEqual(colour(level: 50, threshold: 0), "red")
  }

  /// Neither edge may end up above the other, whatever it's given.
  func testTheBandIsNeverInverted() {
    for threshold in [-10.0, 0, 1, 33.3, 50, 99, 100, 200] {
      let edges = MeterBands.edges(threshold: threshold)
      XCTAssertLessThanOrEqual(edges.warning, edges.critical, "inverted at \(threshold)")
      XCTAssertGreaterThanOrEqual(edges.warning, 0, "negative warning at \(threshold)")
    }
  }
}
