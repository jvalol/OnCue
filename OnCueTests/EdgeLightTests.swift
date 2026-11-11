//
//  EdgeLightTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/20/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import XCTest

class EdgeLightTests: XCTestCase {
  func testSaysSomethingWhileTheEdgeLightIsOnWithACamera() {
    XCTAssertTrue(EdgeLight.shouldWarn(active: true, hasCamera: true))
  }

  func testSaysNothingWhileTheEdgeLightIsOff() {
    XCTAssertFalse(EdgeLight.shouldWarn(active: false, hasCamera: true))
  }

  /// Without a camera there's nothing for Edge Light to attach to, so nothing to explain.
  func testSaysNothingWithoutACamera() {
    XCTAssertFalse(EdgeLight.shouldWarn(active: true, hasCamera: false))
    XCTAssertFalse(EdgeLight.shouldWarn(active: false, hasCamera: false))
  }

  /// On anything before macOS 26.2 the feature doesn't exist, so `isActive` is false and the
  /// warning can never appear.
  func testOlderSystemsNeverWarn() throws {
    if #available(macOS 26.2, *) {
      throw XCTSkip("This Mac has Edge Light; the older-system path can't be exercised here.")
    }
    XCTAssertFalse(EdgeLight.isActive)
  }
}
