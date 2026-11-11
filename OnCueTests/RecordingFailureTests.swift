//
//  RecordingFailureTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/20/26.
//  Copyright © 2026 Jake Van Alstyne
//

import XCTest
import AVFoundation

class RecordingFailureTests: XCTestCase {
  private func posix(_ code: Int32) -> NSError {
    NSError(domain: NSPOSIXErrorDomain, code: Int(code))
  }

  // MARK: - Reading the error

  func testAFullDiskIsRecognised() {
    XCTAssertEqual(RecordingFailure.from(posix(ENOSPC)), .diskFull)
    XCTAssertEqual(RecordingFailure.from(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)),
                   .diskFull)
  }

  func testAMissingDestinationIsRecognised() {
    XCTAssertEqual(RecordingFailure.from(posix(ENOENT)), .destinationMissing)
    XCTAssertEqual(RecordingFailure.from(posix(ENXIO)), .destinationMissing)
  }

  func testAPermissionsFailureIsRecognised() {
    XCTAssertEqual(RecordingFailure.from(posix(EACCES)), .notPermitted)
    XCTAssertEqual(RecordingFailure.from(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)),
                   .notPermitted)
  }

  func testAnythingElseIsJustOther() {
    XCTAssertEqual(RecordingFailure.from(posix(EINVAL)), .other)
    XCTAssertEqual(RecordingFailure.from(NSError(domain: "SomethingElse", code: 1)), .other)
  }

  /// AVFoundation wraps the real cause, so the reason has to be dug out rather than read off the
  /// top-level error, which only ever says the operation couldn't be completed.
  func testTheRealCauseIsFoundUnderneath() {
    let wrapped = NSError(domain: AVFoundationErrorDomain, code: AVError.unknown.rawValue,
                          userInfo: [NSUnderlyingErrorKey: posix(ENOSPC)])
    XCTAssertEqual(RecordingFailure.from(wrapped), .diskFull)
  }

  // MARK: - Whether it's worth saying

  func testASuccessfulRecordingSaysNothing() {
    XCTAssertFalse(RecordingFailure.isWorthSaying(nil))
  }

  /// A recording that captured nothing isn't a failure to write; nothing was there to write, and
  /// the empty file has already been removed.
  func testCapturingNothingIsNotAFailureToWrite() {
    let nothing = NSError(domain: AVFoundationErrorDomain, code: AVError.noDataCaptured.rawValue)
    XCTAssertFalse(RecordingFailure.isWorthSaying(nothing))
  }

  func testARealFailureIsWorthSaying() {
    XCTAssertTrue(RecordingFailure.isWorthSaying(posix(ENOSPC)))
  }
}
