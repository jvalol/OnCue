//
//  LocalizationTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/23/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import XCTest

/// The invariant for spec 0043: every string the app shows has a German that is present and
/// current, and the German in the catalogs is the German in the built app. What these can't
/// check is whether the German is right; that's Jake's, on screen.
///
/// The catalogs are read from the source tree, so these run where the sources are. The English
/// assertions assume the test process runs in English, as it does on this Mac.
class LocalizationTests: XCTestCase {
  private static let sources = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("OnCue")
  private static let catalogs = ["Localizable", "Main", "InfoPlist"]

  private typealias Entry = [String: Any]

  private func catalog(_ name: String) throws -> [String: Entry] {
    let url = LocalizationTests.sources.appendingPathComponent("\(name).xcstrings")
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    XCTAssertEqual(json?["sourceLanguage"] as? String, "en", name)
    return json?["strings"] as? [String: Entry] ?? [:]
  }

  /// The translated value of a plain entry, or nil when it's missing or not marked translated.
  private func translated(_ unit: Any?) -> String? {
    guard let unit = unit as? Entry, let stringUnit = unit["stringUnit"] as? Entry,
      stringUnit["state"] as? String == "translated" else { return nil }
    return stringUnit["value"] as? String
  }

  private func variations(_ localization: Any?) -> [String: Any]? {
    guard let localization = localization as? Entry, let variations = localization["variations"] as? Entry else { return nil }
    return variations["plural"] as? [String: Any]
  }

  // MARK: - The invariant

  /// Every key has a German marked translated. Where the English has plural forms, the German
  /// has the same forms. A key the catalog says not to translate is checked separately below.
  func testEveryStringHasAGermanThatIsCurrent() throws {
    for name in LocalizationTests.catalogs {
      for (key, entry) in try catalog(name) where entry["shouldTranslate"] as? Bool != false {
        let localizations = entry["localizations"] as? Entry ?? [:]
        if let english = variations(localizations["en"]) {
          guard let german = variations(localizations["de"]) else {
            XCTFail("\(name): \(key) has plural forms in English and none in German"); continue
          }
          XCTAssertEqual(Set(english.keys), Set(german.keys), "\(name): \(key) plural forms differ")
          for (form, unit) in german {
            XCTAssertNotNil(translated(unit), "\(name): \(key) [\(form)] German is missing or not current")
          }
        } else {
          XCTAssertNotNil(translated(localizations["de"]), "\(name): \(key) German is missing or not current")
        }
      }
    }
  }

  /// The storyboard carries the template's main menu, which an app without a Dock icon or menu
  /// bar never shows (LSUIElement). Those entries, and only those, are marked not to translate.
  func testOnlyTheHiddenMainMenuIsLeftUntranslated() throws {
    for name in LocalizationTests.catalogs {
      for (key, entry) in try catalog(name) where entry["shouldTranslate"] as? Bool == false {
        let comment = entry["comment"] as? String ?? ""
        let isMenu = comment.contains("Class = \"NSMenuItem\"") || comment.contains("Class = \"NSMenu\"")
        XCTAssertTrue(name == "Main" && isMenu, "\(name): \(key) is marked not to translate but isn't a main-menu item")
      }
    }
  }

  /// Every titled object in the storyboard has its key in the storyboard catalog, so a label
  /// added later can't ship English-only unnoticed. Two kinds the exporter skips are skipped
  /// here too: an empty title, and a pop-up button cell's, which is whichever item is selected.
  func testEveryStoryboardTitleIsInTheCatalog() throws {
    let storyboard = LocalizationTests.sources.appendingPathComponent("Base.lproj/Main.storyboard")
    let document = try XMLDocument(contentsOf: storyboard)
    let keys = Set(try catalog("Main").keys)
    let titled = try document.nodes(forXPath: "//*[@title and @id]").compactMap { $0 as? XMLElement }
    XCTAssertGreaterThan(titled.count, 100)
    for element in titled where element.name != "popUpButtonCell" {
      let id = element.attribute(forName: "id")!.stringValue!
      let title = element.attribute(forName: "title")!.stringValue!
      guard !title.isEmpty else { continue }
      XCTAssertTrue(keys.contains("\(id).title"), "storyboard \(element.name ?? "?") \(id) \"\(title)\" has no catalog entry")
    }
  }

  /// Every `String(localized:)` and `LocalizedStringResource(...)` literal in the app's sources
  /// is a key in the code catalog, with each interpolation standing for one format specifier.
  func testEveryLocalizedLiteralInCodeIsInTheCatalog() throws {
    let keys = Array(try catalog("Localizable").keys)
    let files = try FileManager.default.subpathsOfDirectory(atPath: LocalizationTests.sources.path)
      .filter { $0.hasSuffix(".swift") }
    let literal = try NSRegularExpression(pattern: #"(?:String\(localized|LocalizedStringResource\(): "((?:[^"\\]|\\.)*)""#)
    var found = 0
    for file in files {
      let text = try String(contentsOf: LocalizationTests.sources.appendingPathComponent(file), encoding: .utf8)
      for match in literal.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
        found += 1
        let source = String(text[Range(match.range(at: 1), in: text)!])
        let pattern = LocalizationTests.keyPattern(forLiteral: source)
        let matches = keys.filter { $0.range(of: pattern, options: .regularExpression) != nil }
        XCTAssertEqual(matches.count, 1, "\(file): \"\(source)\" matches \(matches.count) catalog keys, expected one")
      }
    }
    XCTAssertGreaterThan(found, 50)
  }

  /// A Swift literal as a regular expression over catalog keys: interpolations become format
  /// specifiers, escapes become the characters they stand for.
  static func keyPattern(forLiteral literal: String) -> String {
    var pattern = ""
    var rest = Substring(literal)
    while let start = rest.range(of: "\\(") {
      pattern += NSRegularExpression.escapedPattern(for: unescaped(String(rest[..<start.lowerBound])))
      var depth = 1
      var index = start.upperBound
      while depth > 0 && index < rest.endIndex {
        if rest[index] == "(" { depth += 1 } else if rest[index] == ")" { depth -= 1 }
        index = rest.index(after: index)
      }
      pattern += #"%[0-9$]*(@|lld|d)"#
      rest = rest[index...]
    }
    pattern += NSRegularExpression.escapedPattern(for: unescaped(String(rest)))
    return "^" + pattern + "$"
  }

  private static func unescaped(_ text: String) -> String {
    return text.replacingOccurrences(of: "\\n", with: "\n")
      .replacingOccurrences(of: "\\\"", with: "\"")
      .replacingOccurrences(of: "\\\\", with: "\\")
  }

  func testKeyPatternHandlesInterpolationsAndEscapes() {
    let pattern = LocalizationTests.keyPattern(forLiteral: #"OnCue can't write to \(RecordingsFolder.shortPath(url))"#)
    XCTAssertNotNil("OnCue can't write to %@".range(of: pattern, options: .regularExpression))
    XCTAssertNil("OnCue can't write to it".range(of: pattern, options: .regularExpression))
    let seconds = LocalizationTests.keyPattern(forLiteral: #"typically \(typical)s long"#)
    XCTAssertNotNil("typically %llds long".range(of: seconds, options: .regularExpression))
    let lines = LocalizationTests.keyPattern(forLiteral: #"one.\ntwo"#)
    XCTAssertNotNil("one.\ntwo".range(of: lines, options: .regularExpression))
  }

  // MARK: - The built app

  private var german: Bundle {
    let url = Bundle.main.url(forResource: "de", withExtension: "lproj")
    XCTAssertNotNil(url, "the app has no German")
    return Bundle(url: url!)!
  }

  /// The German in the catalogs is the German in the bundle, for each catalog.
  func testTheGermanIsCompiledIntoTheApp() throws {
    let code = try catalog("Localizable")
    let unarmed = translated((code["Unarmed"]?["localizations"] as? Entry)?["de"])
    XCTAssertNotNil(unarmed)
    XCTAssertEqual(german.localizedString(forKey: "Unarmed", value: nil, table: nil), unarmed)
    XCTAssertNotEqual(unarmed, "Unarmed")

    let storyboard = try catalog("Main")
    let soundKey = storyboard.first { ($0.value["comment"] as? String)?.contains("title = \"Sound\"") == true }?.key
    XCTAssertNotNil(soundKey)
    let sound = translated((storyboard[soundKey!]?["localizations"] as? Entry)?["de"])
    XCTAssertEqual(german.localizedString(forKey: soundKey!, value: nil, table: "Main"), sound)
    XCTAssertNotEqual(sound, "Sound")

    let plist = try catalog("InfoPlist")
    let camera = translated((plist["NSCameraUsageDescription"]?["localizations"] as? Entry)?["de"])
    XCTAssertEqual(german.localizedString(forKey: "NSCameraUsageDescription", value: nil, table: "InfoPlist"), camera)
  }

  /// The plural forms compile into a stringsdict the bundle applies: one and many differ.
  func testTheGermanPluralsCompile() {
    let key = "%lld recordings in a row weren't saved: the file couldn't be written"
    let format = german.localizedString(forKey: key, value: nil, table: nil)
    let one = String(format: format, locale: Locale(identifier: "de"), 1)
    let three = String(format: format, locale: Locale(identifier: "de"), 3)
    XCTAssertTrue(one.hasPrefix("Eine Aufnahme"), one)
    XCTAssertTrue(three.hasPrefix("3 Aufnahmen"), three)
    let deleted = german.localizedString(forKey: "The %lld oldest recordings were deleted to stay under your limit", value: nil, table: nil)
    XCTAssertTrue(String(format: deleted, locale: Locale(identifier: "de"), 1).hasPrefix("Die älteste Aufnahme"))
    XCTAssertTrue(String(format: deleted, locale: Locale(identifier: "de"), 5).hasPrefix("Die 5 ältesten"))
  }

  // MARK: - English, unchanged

  func testTheFailureNoticeReadsAsBefore() {
    XCTAssertEqual(RecordingFailure.diskFull.notice(count: 1),
                   "A recording wasn't saved: there's no room left where recordings go")
    XCTAssertEqual(RecordingFailure.diskFull.notice(count: 3),
                   "3 recordings in a row weren't saved: there's no room left where recordings go")
    XCTAssertEqual(RecordingFailure.destinationMissing.notice(count: 1),
                   "A recording wasn't saved: the folder recordings go to isn't there")
    XCTAssertEqual(RecordingFailure.notPermitted.notice(count: 2),
                   "2 recordings in a row weren't saved: OnCue isn't allowed to write where recordings go")
    XCTAssertEqual(RecordingFailure.other.notice(count: 1),
                   "A recording wasn't saved: the file couldn't be written")
  }

  func testTheDeletedNoticeReadsAsBefore() {
    func deleted(_ count: Int) -> String {
      String(localized: "The \(count) oldest recordings were deleted to stay under your limit")
    }
    XCTAssertEqual(deleted(1), "The oldest recording was deleted to stay under your limit")
    XCTAssertEqual(deleted(2), "The 2 oldest recordings were deleted to stay under your limit")
    XCTAssertEqual(deleted(5), "The 5 oldest recordings were deleted to stay under your limit")
  }

  /// The weekday follows the calendar's own language, whatever the app's is.
  func testTheScheduleWeekdayFollowsTheCalendar() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "de_DE")
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    let components = DateComponents(calendar: calendar, year: 2026, month: 9, day: 24, hour: 6)
    let end = calendar.date(from: components)!
    let now = calendar.date(from: DateComponents(calendar: calendar, year: 2026, month: 9, day: 21, hour: 19))!
    XCTAssertTrue(RecordingManager.describe(end: end, now: now, calendar: calendar).contains("Donnerstag"))
  }
}
