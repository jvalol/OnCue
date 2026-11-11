//
//  UpdateNoticeTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 10/2/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import XCTest

class UpdateNoticeTests: XCTestCase {
  private let suite = "OnCueTests.UpdateNotice"
  private var defaults: UserDefaults!

  override func setUp() {
    UserDefaults().removePersistentDomain(forName: suite)
    defaults = UserDefaults(suiteName: suite)
  }

  override func tearDown() {
    UserDefaults().removePersistentDomain(forName: suite)
  }

  func testTheSameVersionIsNoUpdate() {
    XCTAssertNil(UpdateNotice.check(running: "4.20", lastRun: "4.20", fresh: false))
  }

  func testADifferentVersionIsAnUpdateToIt() {
    XCTAssertEqual(UpdateNotice.check(running: "4.20", lastRun: "4.19", fresh: false), .to("4.20"))
  }

  /// A container with settings but no remembered version was running something older than
  /// this: for the store, 3.0.3.
  func testNoRememberedVersionIsAnUpdateFromOlder() {
    XCTAssertEqual(UpdateNotice.check(running: "4.20", lastRun: nil, fresh: false), .fromOlder)
  }

  func testAFreshContainerIsNotAnUpdate() {
    XCTAssertNil(UpdateNotice.check(running: "4.20", lastRun: nil, fresh: true))
  }

  func testNotingAtLaunchRemembersTheVersionAndWhatIsOwed() {
    let notice = UpdateNotice(defaults: defaults)
    notice.note(running: "4.20", fresh: false)
    XCTAssertEqual(notice.pending, .fromOlder)
    XCTAssertEqual(defaults.string(forKey: UpdateNotice.lastRunKey), "4.20")
    // The same version again: still owed, not replaced by nothing.
    notice.note(running: "4.20", fresh: false)
    XCTAssertEqual(notice.pending, .fromOlder)
    // The next update replaces it.
    notice.note(running: "4.21", fresh: false)
    XCTAssertEqual(notice.pending, .to("4.21"))
    notice.clear()
    XCTAssertNil(notice.pending)
    notice.note(running: "4.21", fresh: false)
    XCTAssertNil(notice.pending, "clicked stays clicked until the next update")
  }

  func testAFreshContainerRemembersTheVersionWithoutOwingALine() {
    let notice = UpdateNotice(defaults: defaults)
    notice.note(running: "4.20", fresh: true)
    XCTAssertNil(notice.pending)
    XCTAssertEqual(defaults.string(forKey: UpdateNotice.lastRunKey), "4.20")
  }

  func testTheLinkLandsOnTheVersionsEntry() {
    XCTAssertEqual(UpdateNotice.anchor(for: "4.19"), "v4-19")
    XCTAssertEqual(UpdateNotice.url(for: .to("4.19"), running: "4.19").absoluteString, "https://oncue.jva.lol/changelog/#v4-19")
    XCTAssertEqual(UpdateNotice.url(for: .fromOlder, running: "4.20").absoluteString, "https://oncue.jva.lol/changelog/#v4-20")
  }
}
