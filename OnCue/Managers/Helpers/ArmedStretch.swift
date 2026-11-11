//
//  ArmedStretch.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/26/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import Foundation

/// One armed period, from an arm to its disarm by any route, and what was recorded inside it
/// (spec 0054). The last one worth keeping is remembered in defaults, so coming home and opening
/// the popover answers the question the folder can't: what happened while I was out?
struct ArmedStretch: Equatable {
  static let fromKey = "armedStretchFrom"
  static let toKey = "armedStretchTo"
  /// When the current armed period began, written on arm beside 0045's record so a crash can
  /// still close the stretch at the last minute OnCue was seen.
  static let armedSinceKey = "armedStretchSince"

  /// An empty stretch shorter than this isn't worth a line: it's a setup toggle, not an outing.
  static let minimumEmptySeconds: TimeInterval = 10 * 60
  /// Files whose timestamps fall within this of each other are one event: two cameras name
  /// their files for the same trigger, and a slow keyframe can put them a second apart.
  static let eventTolerance: TimeInterval = 2

  let from: Date
  let to: Date

  var seconds: TimeInterval { to.timeIntervalSince(from) }

  // MARK: - Defaults

  static func read(from defaults: UserDefaults) -> ArmedStretch? {
    guard let from = defaults.object(forKey: fromKey) as? Date,
      let to = defaults.object(forKey: toKey) as? Date, to >= from else { return nil }
    return ArmedStretch(from: from, to: to)
  }

  func write(to defaults: UserDefaults) {
    defaults.set(from, forKey: ArmedStretch.fromKey)
    defaults.set(to, forKey: ArmedStretch.toKey)
  }

  static func noteArmed(at date: Date, in defaults: UserDefaults) {
    defaults.set(date, forKey: armedSinceKey)
  }

  static func armedSince(in defaults: UserDefaults) -> Date? {
    return defaults.object(forKey: armedSinceKey) as? Date
  }

  static func clearArmedSince(in defaults: UserDefaults) {
    defaults.removeObject(forKey: armedSinceKey)
  }

  // MARK: - What happened

  /// One trigger's files: both cameras' movies and their stills.
  struct Event: Equatable {
    let started: Date
    let files: [URL]
  }

  /// The events inside the stretch, oldest first. A recording's footage starts up to `preRoll`
  /// before its trigger, so a file named for a moment just before the arm still belongs to it.
  static func events(in recordings: [DiskBudget.Recording], stretch: ArmedStretch, preRoll: Double) -> [Event] {
    let earliest = stretch.from.addingTimeInterval(-max(preRoll, 0))
    // By time, then by name, so two files from the same second keep a fixed order.
    let inside = recordings
      .filter { $0.started >= earliest && $0.started <= stretch.to }
      .sorted { ($0.started, $0.url.path) < ($1.started, $1.url.path) }
    var events: [Event] = []
    for recording in inside {
      if let last = events.last, recording.started.timeIntervalSince(last.started) <= eventTolerance {
        events[events.count - 1] = Event(started: last.started, files: last.files + [recording.url])
      } else {
        events.append(Event(started: recording.started, files: [recording.url]))
      }
    }
    return events
  }

  /// Every file of every event, oldest first: what Finder is asked to select.
  static func files(of events: [Event]) -> [URL] {
    return events.flatMap { $0.files }
  }

  /// Whether a finished stretch replaces the remembered one: it had an event, or it lasted long
  /// enough to have been an outing rather than a toggle.
  static func isWorthKeeping(_ stretch: ArmedStretch, eventCount: Int) -> Bool {
    return eventCount > 0 || stretch.seconds >= minimumEmptySeconds
  }

  // MARK: - The line

  /// What the popover says under the state while unarmed (spec 0054).
  static func summary(_ stretch: ArmedStretch, events: [Event], calendar: Calendar = .current,
                      locale: Locale = .current) -> String {
    let duration = durationText(stretch.seconds, calendar: calendar)
    guard let first = events.first, let last = events.last else {
      return String(localized: "Armed for \(duration), nothing recorded", comment: "Popover line under the state, after a disarm")
    }
    let time = DateFormatter()
    time.calendar = calendar
    time.timeZone = calendar.timeZone
    time.locale = locale
    time.timeStyle = .short
    time.dateStyle = .none
    if events.count == 1 {
      return String(localized: "Armed for \(duration): one recording at \(time.string(from: first.started))", comment: "Popover line under the state, after a disarm")
    }
    return String(localized: "Armed for \(duration): \(events.count) recordings between \(time.string(from: first.started)) and \(time.string(from: last.started))", comment: "Popover line under the state, after a disarm")
  }

  /// "7:09–7:11 AM", or with the days when the stretch crosses midnight: what the menu items
  /// name so they say which period they act on (spec 0055's first check).
  static func spanText(_ stretch: ArmedStretch, calendar: Calendar = .current, locale: Locale = .current) -> String {
    let formatter = DateIntervalFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = locale
    formatter.timeStyle = .short
    formatter.dateStyle = calendar.isDate(stretch.from, inSameDayAs: stretch.to) ? .none : .short
    return formatter.string(from: stretch.from, to: stretch.to)
  }

  /// "4h 12m", "35s": at most two units, abbreviated, in the user's language.
  static func durationText(_ seconds: TimeInterval, calendar: Calendar = .current) -> String {
    let formatter = DateComponentsFormatter()
    formatter.calendar = calendar
    formatter.unitsStyle = .abbreviated
    formatter.allowedUnits = seconds < 60 ? [.second] : [.day, .hour, .minute]
    formatter.maximumUnitCount = 2
    formatter.zeroFormattingBehavior = .dropAll
    return formatter.string(from: max(seconds, 0)) ?? ""
  }
}
