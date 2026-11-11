//
//  CaptureDemandTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/20/26.
//  Copyright © 2026 Jake Van Alstyne
//

import XCTest

class CaptureDemandTests: XCTestCase {
  func shouldCapture(_ state: RecordingManager.ArmState, popover: Bool = false, preview: Bool = false) -> Bool {
    CaptureDemand.shouldCapture(armState: state, popoverOpen: popover, previewOpen: preview)
  }

  func testNothingNeedsTheCamerasWhenUnarmedAndNothingIsOpen() {
    XCTAssertFalse(shouldCapture(.unarmed))
  }

  func testAnyArmStateButUnarmedHoldsTheCamerasOpen() {
    XCTAssertTrue(shouldCapture(.arming))
    XCTAssertTrue(shouldCapture(.armed))
    XCTAssertTrue(shouldCapture(.recording))
  }

  func testThePopoverAndThePreviewEachHoldTheCamerasOpen() {
    XCTAssertTrue(shouldCapture(.unarmed, popover: true))
    XCTAssertTrue(shouldCapture(.unarmed, preview: true))
    XCTAssertTrue(shouldCapture(.unarmed, popover: true, preview: true))
  }

  /// Closing the popover mid-recording must not stop capture: the recording is its own reason.
  func testClosingThePopoverWhileRecordingKeepsTheCamerasOpen() {
    XCTAssertTrue(shouldCapture(.recording, popover: false))
  }

  func testCaptureStopsOnlyWhenNothingNeedsItAndNoFileIsBeingWritten() {
    XCTAssertTrue(CaptureDemand.canStop(shouldCapture: false, writingFiles: false))
    XCTAssertFalse(CaptureDemand.canStop(shouldCapture: true, writingFiles: false))
  }

  /// Disarming during a recording clears the arm state before the files finish, so the rule that
  /// says "nothing needs capture" arrives while a writer is still open. Stopping then would cut
  /// the file short, leaving it with no index.
  func testAFileStillBeingWrittenKeepsCaptureOpen() {
    XCTAssertFalse(CaptureDemand.canStop(shouldCapture: false, writingFiles: true))
    XCTAssertFalse(CaptureDemand.canStop(shouldCapture: true, writingFiles: true))
  }
}
