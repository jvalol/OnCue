//
//  AccessibilityTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 10/21/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import XCTest

/// Every control a screen reader lands on has a name (spec 0049). The walk is over the real
/// storyboard scenes, so a control added later without a label fails here rather than in
/// someone's ears.
class AccessibilityTests: XCTestCase {
  /// The scenes come from the app's storyboard at run time: the tests run inside the app, and
  /// the view controllers aren't compiled into the test target, so they're reached by name.
  private func popover() -> NSViewController {
    let storyboard = NSStoryboard(name: "Main", bundle: Bundle.main)
    let controller = storyboard.instantiateController(withIdentifier: "PopoverViewController") as! NSViewController
    _ = controller.view
    return controller
  }

  private func settings() -> NSViewController {
    let storyboard = NSStoryboard(name: "Main", bundle: Bundle.main)
    let window = storyboard.instantiateController(withIdentifier: "SettingsWindowController") as! NSWindowController
    let controller = window.contentViewController!
    _ = controller.view
    return controller
  }

  /// Controls a reader stops on: everything interactive, and the meters. Labels (non-editable
  /// text fields) are what the names come from, not what needs one.
  private func controls(in view: NSView) -> [NSView] {
    var found: [NSView] = []
    for subview in view.subviews {
      if let field = subview as? NSTextField, !field.isEditable {
        // A label, or the path field, which is named explicitly and checked below.
      } else if subview is NSControl {
        found.append(subview)
      }
      found.append(contentsOf: controls(in: subview))
    }
    return found
  }

  private func name(of view: NSView) -> String? {
    if let label = view.accessibilityLabel(), !label.isEmpty { return label }
    if let titled = view.accessibilityTitleUIElement() as? NSTextField, !titled.stringValue.isEmpty { return titled.stringValue }
    if let button = view as? NSButton, !(button is NSPopUpButton), !button.title.isEmpty { return button.title }
    return nil
  }

  private func assertEveryControlIsNamed(in view: NSView, _ place: String) {
    let all = controls(in: view)
    XCTAssertGreaterThan(all.count, 5, place)
    for control in all {
      XCTAssertNotNil(name(of: control), "\(place): \(type(of: control)) at \(control.frame) has no accessibility name")
    }
  }

  func testEveryPopoverControlIsNamed() {
    assertEveryControlIsNamed(in: popover().view, "popover")
  }

  func testTheMetersSpeakTheirLevel() {
    let popover = popover()
    let meters = controls(in: popover.view).compactMap { $0 as? NSLevelIndicator }
    XCTAssertEqual(meters.count, 3)
    for (meter, level) in zip(meters, [40.0, 7.0, 73.0]) { meter.doubleValue = level }
    popover.perform(NSSelectorFromString("describeMetersForAccessibility"))
    let spoken = meters.map { $0.accessibilityValueDescription() ?? "" }
    for value in ["40", "7", "73"] {
      XCTAssertTrue(spoken.contains { $0.contains(value) }, "no meter says \(value): \(spoken)")
    }
  }

  func testEverySettingsControlIsNamed() {
    // A schedule row, so the weekday boxes, the pickers and the minus button are in the walk.
    let defaults = UserDefaults.standard
    let saved = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("schedule") }
    Schedule(windows: [ScheduleWindow(days: [2, 3, 4, 5, 6], start: 9 * 60, end: 17 * 60)]).save(to: defaults)
    defer {
      for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("schedule") { defaults.removeObject(forKey: key) }
      for (key, value) in saved { defaults.set(value, forKey: key) }
    }
    let settings = settings()
    assertEveryControlIsNamed(in: settings.view, "settings")
    let weekdays = controls(in: settings.view).compactMap { $0 as? NSButton }.filter { $0.tag >= 1 && $0.tag <= 7 }
    XCTAssertEqual(weekdays.count, 7)
    XCTAssertEqual(Set(weekdays.compactMap { $0.accessibilityLabel() }), Set(Calendar.current.weekdaySymbols))
  }

  func testTheSettingsLabelsNameTheControlsBesideThem() {
    let settings = settings()
    let titled = controls(in: settings.view).compactMap { $0.accessibilityTitleUIElement() as? NSTextField }.map { $0.stringValue }
    for expected in ["Camera", "Second camera", "Microphone"] {
      XCTAssertTrue(titled.contains(expected), "no control is titled by the \(expected) label: \(titled)")
    }
    XCTAssertEqual(titled.count, 6, "three pop-ups and three number fields")
  }
}
