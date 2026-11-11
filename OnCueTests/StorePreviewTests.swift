//
//  StorePreviewTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 11/9/26.
//  Copyright © 2026 Jake Van Alstyne
//

import XCTest

/// The preview's storyboard adds up (spec 0061): inside Apple's bounds, every frame in a scene,
/// the captions numbered without gaps, and the story in the order the spec tells it.
class StorePreviewTests: XCTestCase {
  func testTheClipIsWithinApplesBounds() {
    XCTAssertGreaterThanOrEqual(StorePreviewStoryboard.totalSeconds, StorePreviewStoryboard.shortestSeconds)
    XCTAssertLessThanOrEqual(StorePreviewStoryboard.totalSeconds, StorePreviewStoryboard.longestSeconds)
    XCTAssertEqual(StorePreviewStoryboard.frameCount, Int(StorePreviewStoryboard.totalSeconds) * StorePreviewStoryboard.framesPerSecond)
  }

  func testEveryFrameFallsInAScene() {
    for frame in 0..<StorePreviewStoryboard.frameCount {
      XCTAssertNotNil(StorePreviewStoryboard.scene(atFrame: frame), "frame \(frame)")
    }
    XCTAssertNil(StorePreviewStoryboard.scene(atFrame: StorePreviewStoryboard.frameCount), "one past the end")
    XCTAssertEqual(StorePreviewStoryboard.scene(atFrame: 0)?.index, 0)
    XCTAssertEqual(StorePreviewStoryboard.scene(atFrame: StorePreviewStoryboard.frameCount - 1)?.index, StorePreviewStoryboard.scenes.count - 1)
  }

  func testCaptionsAreNumberedWithoutGaps() {
    let used = Set(StorePreviewStoryboard.scenes.map(\.caption))
    XCTAssertEqual(used, Set(0..<StorePreviewStoryboard.captionCount))
    XCTAssertEqual(StorePreviewStoryboard.captionCount, 6)
  }

  func testTheStoryIsToldInOrder() {
    let states = StorePreviewStoryboard.scenes.map(\.state)
    XCTAssertEqual(states.first, .unarmed)
    XCTAssertLessThan(states.firstIndex(of: .arming)!, states.firstIndex(of: .armed)!)
    XCTAssertLessThan(states.firstIndex(of: .armed)!, states.firstIndex(of: .recording)!)
    let countdowns = StorePreviewStoryboard.scenes.filter { $0.state == .arming }.map(\.countdown)
    XCTAssertEqual(countdowns, [3, 2, 1], "the count visibly counts")
  }

  func testMeterLevelsStayOnTheScaleAndMove() {
    let range = (from: 10.0, to: 40.0)
    let start = StorePreviewStoryboard.level(range, progress: 0, wobble: 0)
    let end = StorePreviewStoryboard.level(range, progress: 1, wobble: 0)
    XCTAssertEqual(start, 10, accuracy: 0.001)
    XCTAssertEqual(end, 40, accuracy: 0.001)
    for phase in stride(from: 0.0, through: 30.0, by: 0.37) {
      let level = StorePreviewStoryboard.level((from: 0, to: 100), progress: phase / 30, wobble: phase)
      XCTAssertGreaterThanOrEqual(level, 0)
      XCTAssertLessThanOrEqual(level, 100)
    }
  }
}
