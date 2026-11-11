//
//  FreshStartTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/22/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import XCTest

class FreshStartTests: XCTestCase {
  private var defaults: UserDefaults!
  private let suite = "OnCueTests.FreshStart"

  override func setUp() {
    super.setUp()
    UserDefaults().removePersistentDomain(forName: suite)
    defaults = UserDefaults(suiteName: suite)
  }

  override func tearDown() {
    UserDefaults().removePersistentDomain(forName: suite)
    super.tearDown()
  }

  /// A container that already has settings never begins a fresh start, so nothing is pending.
  func testAnOrdinaryLaunchHasNothingToSay() {
    XCTAssertFalse(FreshStart(defaults: defaults).isPending)
  }

  func testTheFirstLaunchLeavesTheNoticePending() {
    let fresh = FreshStart(defaults: defaults)
    fresh.begin()
    XCTAssertTrue(fresh.isPending)
  }

  /// Stored, not remembered: a relaunch before anyone looked still shows it.
  func testItSurvivesARelaunchUntilSomeoneLooks() {
    FreshStart(defaults: defaults).begin()
    XCTAssertTrue(FreshStart(defaults: defaults).isPending)
  }

  func testOnceClearedItStaysCleared() {
    let fresh = FreshStart(defaults: defaults)
    fresh.begin()
    fresh.clear()
    XCTAssertFalse(fresh.isPending)
    XCTAssertFalse(FreshStart(defaults: defaults).isPending)
  }
}
