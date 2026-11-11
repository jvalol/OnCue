//
//  ArmedStretchTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/26/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import XCTest

class ArmedStretchTests: XCTestCase {
  private let suite = "OnCueTests.ArmedStretch"
  private var defaults: UserDefaults!
  private let noon = Date(timeIntervalSince1970: 1_790_000_000)

  private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
  }

  override func setUp() {
    UserDefaults().removePersistentDomain(forName: suite)
    defaults = UserDefaults(suiteName: suite)
  }

  override func tearDown() {
    UserDefaults().removePersistentDomain(forName: suite)
  }

  private func recording(_ secondsAfterNoon: TimeInterval, name: String) -> DiskBudget.Recording {
    DiskBudget.Recording(url: URL(fileURLWithPath: "/tmp/\(name)"),
                         started: noon.addingTimeInterval(secondsAfterNoon), bytes: 1)
  }

  // MARK: - Defaults

  func testAStretchRoundTripsThroughDefaults() {
    let stretch = ArmedStretch(from: noon, to: noon.addingTimeInterval(3600))
    XCTAssertNil(ArmedStretch.read(from: defaults))
    stretch.write(to: defaults)
    XCTAssertEqual(ArmedStretch.read(from: defaults), stretch)
  }

  func testTheArmMomentIsKeptUntilCleared() {
    XCTAssertNil(ArmedStretch.armedSince(in: defaults))
    ArmedStretch.noteArmed(at: noon, in: defaults)
    XCTAssertEqual(ArmedStretch.armedSince(in: defaults), noon)
    ArmedStretch.clearArmedSince(in: defaults)
    XCTAssertNil(ArmedStretch.armedSince(in: defaults))
  }

  // MARK: - What happened

  func testOnlyRecordingsInsideTheStretchCount() {
    let stretch = ArmedStretch(from: noon, to: noon.addingTimeInterval(3600))
    let before = recording(-600, name: "before.mov"), during = recording(100, name: "during.mov"), after = recording(4000, name: "after.mov")
    let events = ArmedStretch.events(in: [after, before, during], stretch: stretch, preRoll: 5)
    XCTAssertEqual(events.map { $0.files }, [[during.url]])
  }

  func testPreRollLetsAFileNamedJustBeforeTheArmBelong() {
    let stretch = ArmedStretch(from: noon, to: noon.addingTimeInterval(3600))
    let justBefore = recording(-4, name: "just.mov"), tooEarly = recording(-6, name: "early.mov")
    let events = ArmedStretch.events(in: [tooEarly, justBefore], stretch: stretch, preRoll: 5)
    XCTAssertEqual(events.map { $0.files }, [[justBefore.url]])
  }

  /// Two cameras name their files for the same trigger, a second apart at most; the stills share
  /// the movies' names. That's one event with four files, not four events.
  func testBothCamerasFilesAndStillsAreOneEvent() {
    let stretch = ArmedStretch(from: noon, to: noon.addingTimeInterval(3600))
    let files = [recording(100, name: "a.mov"), recording(100, name: "a.jpg"),
                 recording(101, name: "b.mov"), recording(101, name: "b.jpg"),
                 recording(400, name: "c.mov"), recording(400, name: "c.jpg")]
    let events = ArmedStretch.events(in: files.reversed(), stretch: stretch, preRoll: 0)
    XCTAssertEqual(events.count, 2)
    XCTAssertEqual(events[0].files.count, 4)
    XCTAssertEqual(events[1].files.count, 2)
    XCTAssertEqual(ArmedStretch.files(of: events).map { $0.lastPathComponent },
                   ["a.jpg", "a.mov", "b.jpg", "b.mov", "c.jpg", "c.mov"])
  }

  func testTriggersMoreThanTwoSecondsApartAreSeparateEvents() {
    let stretch = ArmedStretch(from: noon, to: noon.addingTimeInterval(3600))
    let events = ArmedStretch.events(in: [recording(100, name: "a.mov"), recording(103, name: "b.mov")],
                                     stretch: stretch, preRoll: 0)
    XCTAssertEqual(events.count, 2)
  }

  // MARK: - Worth a line

  func testAStretchWithARecordingIsAlwaysKept() {
    XCTAssertTrue(ArmedStretch.isWorthKeeping(ArmedStretch(from: noon, to: noon.addingTimeInterval(5)), eventCount: 1))
  }

  func testAnEmptyStretchNeedsTenMinutes() {
    XCTAssertFalse(ArmedStretch.isWorthKeeping(ArmedStretch(from: noon, to: noon.addingTimeInterval(599)), eventCount: 0))
    XCTAssertTrue(ArmedStretch.isWorthKeeping(ArmedStretch(from: noon, to: noon.addingTimeInterval(600)), eventCount: 0))
  }

  // MARK: - The line

  func testDurationsReadAsAtMostTwoUnits() {
    XCTAssertEqual(ArmedStretch.durationText(35, calendar: utc), "35s")
    XCTAssertEqual(ArmedStretch.durationText(4 * 3600 + 12 * 60 + 30, calendar: utc), "4h 12m")
    XCTAssertEqual(ArmedStretch.durationText(26 * 3600, calendar: utc), "1d 2h")
  }

  func testTheLineForNothing() {
    let stretch = ArmedStretch(from: noon, to: noon.addingTimeInterval(4 * 3600))
    let line = ArmedStretch.summary(stretch, events: [], calendar: utc, locale: Locale(identifier: "en_US_POSIX"))
    XCTAssertTrue(line.hasPrefix("Armed for 4h"), line)
    XCTAssertTrue(line.contains("nothing recorded"), line)
  }

  func testTheLineForOneAndForMany() {
    let stretch = ArmedStretch(from: noon, to: noon.addingTimeInterval(4 * 3600))
    let one = ArmedStretch.events(in: [recording(600, name: "a.mov")], stretch: stretch, preRoll: 0)
    let oneLine = ArmedStretch.summary(stretch, events: one, calendar: utc, locale: Locale(identifier: "en_US_POSIX"))
    XCTAssertTrue(oneLine.contains("one recording at"), oneLine)
    let many = ArmedStretch.events(in: [recording(600, name: "a.mov"), recording(3000, name: "b.mov"), recording(7000, name: "c.mov")],
                                   stretch: stretch, preRoll: 0)
    let manyLine = ArmedStretch.summary(stretch, events: many, calendar: utc, locale: Locale(identifier: "en_US_POSIX"))
    XCTAssertTrue(manyLine.contains("3 recordings between"), manyLine)
  }

  func testTheSpanNamesTheTimesAndTheDaysOnlyAcrossMidnight() {
    let posix = Locale(identifier: "en_US_POSIX")
    let sameDay = ArmedStretch(from: noon, to: noon.addingTimeInterval(2 * 3600))
    // The formatter's own spacing (narrow spaces around the dash and before PM) isn't the point.
    let same = ArmedStretch.spanText(sameDay, calendar: utc, locale: posix)
    XCTAssertTrue(same.contains("2:13") && same.contains("4:13") && same.contains("PM") && !same.contains("2026"), same)
    let overnight = ArmedStretch(from: noon.addingTimeInterval(8 * 3600), to: noon.addingTimeInterval(11 * 3600))
    let span = ArmedStretch.spanText(overnight, calendar: utc, locale: posix)
    XCTAssertTrue(span.contains("9/21") || span.contains("2026"), span)
  }

  // MARK: - The menu

  func testTheMenuItemNeedsAStretchWithFiles() {
    let stretch = ArmedStretch(from: noon, to: noon.addingTimeInterval(3600))
    XCTAssertFalse(RecordingManager.WhatHappened(stretch: stretch, events: []).canShow)
    let event = ArmedStretch.Event(started: noon, files: [URL(fileURLWithPath: "/tmp/a.mov")])
    XCTAssertTrue(RecordingManager.WhatHappened(stretch: stretch, events: [event]).canShow)
  }
}
