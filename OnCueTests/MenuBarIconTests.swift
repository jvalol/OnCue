//
//  MenuBarIconTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/19/26.
//  Copyright © 2026 Jake Van Alstyne
//

import XCTest

class MenuBarIconTests: XCTestCase {
  func testUnarmedIsMonochromeForTheMenuBarToTint() {
    XCTAssertTrue(MenuBarIcon.appearance(for: .unarmed).isTemplate)
  }

  func testEachActiveStateHasItsOwnColors() {
    XCTAssertEqual(MenuBarIcon.appearance(for: .arming), .init(isTemplate: false, ring: .orange, center: .gray))
    XCTAssertEqual(MenuBarIcon.appearance(for: .armed), .init(isTemplate: false, ring: .red, center: .blue))
    XCTAssertEqual(MenuBarIcon.appearance(for: .recording), .init(isTemplate: false, ring: .red, center: .red))
  }

  func testNoTwoStatesLookAlike() {
    let states: [RecordingManager.ArmState] = [.unarmed, .arming, .armed, .recording]
    let appearances = states.map { MenuBarIcon.appearance(for: $0) }
    for (i, a) in appearances.enumerated() {
      for b in appearances[(i + 1)...] {
        XCTAssertNotEqual(a, b)
      }
    }
  }
}
