//
//  MotionDetectorTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 4/10/20.
//  Copyright © 2020 Jake Van Alstyne
//

import XCTest

class MotionDetectorTests: XCTestCase {
  func testMotionLevelIsFullScaleAtFivePercent() {
    XCTAssertEqual(MotionDetector.motionLevel(pixelsWithMotion: 0, pixelsTested: 1000), 0)
    XCTAssertEqual(MotionDetector.motionLevel(pixelsWithMotion: 25, pixelsTested: 1000), 50, accuracy: 0.0001)
    XCTAssertEqual(MotionDetector.motionLevel(pixelsWithMotion: 50, pixelsTested: 1000), 100, accuracy: 0.0001)
    XCTAssertEqual(MotionDetector.motionLevel(pixelsWithMotion: 100, pixelsTested: 1000), 200, accuracy: 0.0001)
  }

  func testMotionLevelWithNothingTested() {
    XCTAssertEqual(MotionDetector.motionLevel(pixelsWithMotion: 0, pixelsTested: 0), 0)
  }

  func testReportsMotionAboveThreshold() {
    XCTAssertFalse(MotionDetector.detectMotion(pixelsWithMotion: 0, pixelsTested: 1000, threshold: 50, enabled: true))
    XCTAssertFalse(MotionDetector.detectMotion(pixelsWithMotion: 25, pixelsTested: 1000, threshold: 50, enabled: true))
    XCTAssertTrue(MotionDetector.detectMotion(pixelsWithMotion: 26, pixelsTested: 1000, threshold: 50, enabled: true))
  }

  func testEachCameraKeepsItsOwnThreshold() {
    let defaults = UserDefaults(suiteName: "OnCueTests.Thresholds")!
    defaults.removePersistentDomain(forName: "OnCueTests.Thresholds")
    defer { defaults.removePersistentDomain(forName: "OnCueTests.Thresholds") }

    MotionDetector.setThreshold(30, cameraID: "built-in", defaults: defaults)
    MotionDetector.setThreshold(60, cameraID: "webcam", defaults: defaults)

    XCTAssertEqual(MotionDetector.threshold(cameraID: "built-in", defaults: defaults), 30)
    XCTAssertEqual(MotionDetector.threshold(cameraID: "webcam", defaults: defaults), 60)
  }

  func testANewCameraStartsAtTheLastThresholdSet() {
    let defaults = UserDefaults(suiteName: "OnCueTests.Thresholds")!
    defaults.removePersistentDomain(forName: "OnCueTests.Thresholds")
    defer { defaults.removePersistentDomain(forName: "OnCueTests.Thresholds") }

    MotionDetector.setThreshold(45, cameraID: "built-in", defaults: defaults)

    XCTAssertEqual(MotionDetector.threshold(cameraID: "webcam", defaults: defaults), 45)
    XCTAssertEqual(MotionDetector.threshold(cameraID: nil, defaults: defaults), 45)
  }

  func testNeverReportsMotionWhenDisabled() {
    XCTAssertFalse(MotionDetector.detectMotion(pixelsWithMotion: 1000, pixelsTested: 1000, threshold: 0, enabled: false))
  }

  func testAnyMotionTriggersAtZeroThreshold() {
    XCTAssertFalse(MotionDetector.detectMotion(pixelsWithMotion: 0, pixelsTested: 1000, threshold: 0, enabled: true))
    XCTAssertTrue(MotionDetector.detectMotion(pixelsWithMotion: 1, pixelsTested: 1000, threshold: 0, enabled: true))
  }
}
