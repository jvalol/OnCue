//
//  PreviewTitleTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/19/26.
//  Copyright © 2026 Jake Van Alstyne
//

import XCTest

class PreviewTitleTests: XCTestCase {
  func testNamesTheCameraInUse() {
    XCTAssertEqual(PreviewTitle.title(cameraName: "MacBook Pro Camera"), "OnCue - MacBook Pro Camera")
  }

  func testNamesBothCameras() {
    XCTAssertEqual(PreviewTitle.title(cameraNames: ["MacBook Pro Camera", "HD Pro Webcam C920"]),
                   "OnCue - MacBook Pro Camera + HD Pro Webcam C920")
  }

  func testWindowSizeHoldsTheCamerasWithNoBlackBars() {
    let oneCamera = PreviewTitle.contentSize(fitting: CGSize(width: 1920, height: 1080), width: 640, maximum: nil)
    XCTAssertEqual(oneCamera, CGSize(width: 640, height: 360))

    let twoCameras = PreviewTitle.contentSize(fitting: CGSize(width: 3840, height: 1080), width: 1280, maximum: nil)
    XCTAssertEqual(twoCameras, CGSize(width: 1280, height: 360))
  }

  func testWindowSizeStaysOnScreen() {
    let screen = CGSize(width: 1000, height: 300)
    let size = PreviewTitle.contentSize(fitting: CGSize(width: 3840, height: 1080), width: 1280, maximum: screen)
    XCTAssertLessThanOrEqual(size.width, screen.width)
    XCTAssertLessThanOrEqual(size.height, screen.height)
    XCTAssertEqual(size.height, (size.width * 1080 / 3840).rounded())
  }

  func testIsJustOnCueWithNoCamera() {
    XCTAssertEqual(PreviewTitle.title(cameraName: nil), "OnCue")
  }
}
