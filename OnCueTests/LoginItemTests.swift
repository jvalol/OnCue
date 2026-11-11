//
//  LoginItemTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/19/26.
//  Copyright © 2026 Jake Van Alstyne
//

import XCTest
import ServiceManagement

class FakeLoginItemService: LoginItemService {
  var status: SMAppService.Status = .notRegistered
  var failure: Error?
  var statusAfterRegister: SMAppService.Status = .enabled

  func register() throws {
    if let failure = failure { throw failure }
    status = statusAfterRegister
  }

  func unregister() throws {
    if let failure = failure { throw failure }
    status = .notRegistered
  }
}

class LoginItemTests: XCTestCase {
  func testReadsWhatMacOSHas() {
    XCTAssertEqual(LoginItem.state(for: .enabled), .on)
    XCTAssertEqual(LoginItem.state(for: .notRegistered), .off)
    XCTAssertEqual(LoginItem.state(for: .notFound), .off)
    XCTAssertEqual(LoginItem.state(for: .requiresApproval), .needsApproval)
  }

  func testSwitchedOffInSystemSettingsShowsUnchecked() {
    XCTAssertTrue(LoginItem.isChecked(.on))
    XCTAssertFalse(LoginItem.isChecked(.off))
    XCTAssertFalse(LoginItem.isChecked(LoginItem.state(for: .requiresApproval)))
  }

  func testTurningOnAndOff() {
    let service = FakeLoginItemService()
    let item = LoginItem(service: service)
    XCTAssertEqual(item.set(true).state, .on)
    XCTAssertEqual(item.set(false).state, .off)
  }

  func testApprovalNeededIsReported() {
    let service = FakeLoginItemService()
    service.statusAfterRegister = .requiresApproval
    XCTAssertEqual(LoginItem(service: service).set(true).state, .needsApproval)
  }

  func testAFailureReportsTheErrorAndTheRealState() {
    let service = FakeLoginItemService()
    service.failure = NSError(domain: "test", code: 1)
    let result = LoginItem(service: service).set(true)
    XCTAssertNotNil(result.error)
    XCTAssertEqual(result.state, .off)
  }
}
