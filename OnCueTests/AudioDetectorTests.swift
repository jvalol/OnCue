//
//  AudioDetectorTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/19/26.
//  Copyright © 2026 Jake Van Alstyne
//

import XCTest

class AudioDetectorTests: XCTestCase {
  func testLevelIsLinearInDecibelsFromFloorToFullScale() {
    XCTAssertEqual(AudioDetector.level(decibels: -60), 0, accuracy: 0.0001)
    XCTAssertEqual(AudioDetector.level(decibels: -30), 50, accuracy: 0.0001)
    XCTAssertEqual(AudioDetector.level(decibels: -18), 70, accuracy: 0.0001)
    XCTAssertEqual(AudioDetector.level(decibels: 0), 100, accuracy: 0.0001)
  }

  func testLevelClampsOutsideTheScale() {
    XCTAssertEqual(AudioDetector.level(decibels: -160), 0)
    XCTAssertEqual(AudioDetector.level(decibels: 3), 100)
  }

  func testSilenceAndInvalidReadingsAreZero() {
    XCTAssertEqual(AudioDetector.level(decibels: -.infinity), 0)
    XCTAssertEqual(AudioDetector.level(decibels: .nan), 0)
  }

  func testDetectsSoundAboveThresholdWhenEnabled() {
    XCTAssertFalse(AudioDetector.detectSound(level: 70, threshold: 70, enabled: true))
    XCTAssertTrue(AudioDetector.detectSound(level: 71, threshold: 70, enabled: true))
  }

  func testNeverDetectsSoundWhenDisabled() {
    XCTAssertFalse(AudioDetector.detectSound(level: 100, threshold: 0, enabled: false))
  }
}
