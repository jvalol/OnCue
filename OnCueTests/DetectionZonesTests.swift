//
//  DetectionZonesTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/22/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import XCTest

class DetectionZonesTests: XCTestCase {
  private let width = 200, height = 100
  private let leftHalf = CGRect(x: 0, y: 0, width: 0.5, height: 1)
  private let topRightCorner = CGRect(x: 0.75, y: 0, width: 0.25, height: 0.25)

  /// No zones: the whole picture counts, as it always has.
  func testNoZonesMeansEverything() {
    let none = DetectionZones()
    XCTAssertTrue(none.contains(x: 0, y: 0, width: width, height: height))
    XCTAssertTrue(none.contains(x: 199, y: 99, width: width, height: height))
    let (tested, _) = none.count(width: width, height: height, stride: 20) { _, _ in false }
    XCTAssertEqual(tested, 10 * 5, "every 20th pixel on each axis, nothing skipped")
  }

  func testMembershipIsInNormalisedPictureCoordinates() {
    let zones = DetectionZones(rects: [leftHalf])
    XCTAssertTrue(zones.contains(x: 0, y: 50, width: width, height: height))
    XCTAssertTrue(zones.contains(x: 99, y: 50, width: width, height: height))
    XCTAssertFalse(zones.contains(x: 100, y: 50, width: width, height: height))
    XCTAssertFalse(zones.contains(x: 199, y: 50, width: width, height: height))
  }

  /// The same rectangle covers the same part of the picture whatever the resolution.
  func testZonesSurviveAResolutionChange() {
    let zones = DetectionZones(rects: [topRightCorner])
    XCTAssertTrue(zones.contains(x: 1800, y: 100, width: 1920, height: 1080))
    XCTAssertTrue(zones.contains(x: 1200, y: 60, width: 1280, height: 720))
    XCTAssertFalse(zones.contains(x: 100, y: 100, width: 1920, height: 1080))
    XCTAssertFalse(zones.contains(x: 1800, y: 900, width: 1920, height: 1080))
  }

  func testAnyOfSeveralZonesCounts() {
    let zones = DetectionZones(rects: [leftHalf, topRightCorner])
    XCTAssertTrue(zones.contains(x: 10, y: 90, width: width, height: height), "left half")
    XCTAssertTrue(zones.contains(x: 190, y: 5, width: width, height: height), "top right")
    XCTAssertFalse(zones.contains(x: 190, y: 90, width: width, height: height), "bottom right, neither")
  }

  /// The zone is the universe: motion filling a zone that is a quarter of the picture reads as
  /// every tested pixel moving, not a quarter of them.
  func testTheLevelIsAFractionOfTheZoneNotTheFrame() {
    let zones = DetectionZones(rects: [topRightCorner])
    // Motion everywhere in the top-right quarter, nowhere else.
    let (tested, withMotion) = zones.count(width: width, height: height, stride: 20) { x, y in x >= 150 && y < 25 }
    XCTAssertGreaterThan(tested, 0)
    XCTAssertEqual(withMotion, tested, "everything inside the zone moved")
    let whole = DetectionZones()
    let (allTested, allWithMotion) = whole.count(width: width, height: height, stride: 20) { x, y in x >= 150 && y < 25 }
    XCTAssertLessThan(allWithMotion, allTested / 4 + 1, "against the whole frame the same motion is a sliver")
  }

  func testMotionOutsideEveryZoneIsNotCounted() {
    let zones = DetectionZones(rects: [leftHalf])
    let (tested, withMotion) = zones.count(width: width, height: height, stride: 20) { x, _ in x >= 100 }
    XCTAssertGreaterThan(tested, 0)
    XCTAssertEqual(withMotion, 0)
  }

  func testStoredPerCameraAndRoundTrips() {
    let suite = "OnCueTests.DetectionZones"
    UserDefaults().removePersistentDomain(forName: suite)
    let defaults = UserDefaults(suiteName: suite)!
    XCTAssertEqual(DetectionZones.load(cameraID: "a", defaults: defaults), DetectionZones())
    XCTAssertEqual(DetectionZones.load(cameraID: nil, defaults: defaults), DetectionZones())
    DetectionZones(rects: [leftHalf]).save(cameraID: "a", defaults: defaults)
    DetectionZones(rects: [topRightCorner]).save(cameraID: "b", defaults: defaults)
    XCTAssertEqual(DetectionZones.load(cameraID: "a", defaults: defaults).rects, [leftHalf])
    XCTAssertEqual(DetectionZones.load(cameraID: "b", defaults: defaults).rects, [topRightCorner])
    XCTAssertEqual(DetectionZones.current(cameraID: "a", defaults: defaults).rects, [leftHalf], "what the pipeline reads")
    DetectionZones().save(cameraID: "a", defaults: defaults)
    XCTAssertTrue(DetectionZones.current(cameraID: "a", defaults: defaults).isEmpty, "cleared, and the cache followed")
    UserDefaults().removePersistentDomain(forName: suite)
  }
}
