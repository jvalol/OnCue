//
//  Schedule.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/22/26.
//  Copyright © 2026 Jake Van Alstyne
//

import Foundation

/// One stretch of the week during which OnCue arms itself (spec 0038). Times are minutes after
/// midnight; days are `Calendar` weekday numbers, 1 for Sunday through 7 for Saturday, and name
/// the day the window *starts* on. A window from 22:00 to 06:00 on Friday runs into Saturday
/// morning whatever Saturday's own setting is.
struct ScheduleWindow: Equatable, Codable {
  var days: Set<Int>
  var start: Int
  var end: Int

  static let minutesPerDay = 24 * 60

  /// Whether `date` falls inside this window, on a day it applies to. Start is inclusive and end
  /// exclusive, so a window ending at 17:00 is over at 17:00 exactly. A zero-length window is
  /// nothing, not all day: a row someone hasn't filled in yet shouldn't arm anything.
  func contains(_ date: Date, calendar: Calendar) -> Bool {
    guard start != end else { return false }
    let weekday = calendar.component(.weekday, from: date)
    let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    if start < end {
      return days.contains(weekday) && minutes >= start && minutes < end
    }
    // Crosses midnight: the evening half belongs to today, the morning half to the day before.
    let yesterday = weekday == 1 ? 7 : weekday - 1
    return (days.contains(weekday) && minutes >= start) || (days.contains(yesterday) && minutes < end)
  }

  /// When the window containing `date` ends, or nil if `date` isn't inside it.
  func end(of date: Date, calendar: Calendar) -> Date? {
    guard contains(date, calendar: calendar) else { return nil }
    let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    var day = calendar.startOfDay(for: date)
    if start > end && minutes >= start {
      // Evening half of a window that crosses midnight: it ends tomorrow.
      day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
    }
    return calendar.date(byAdding: .minute, value: end, to: day)
  }

  /// The first moment after `date` at which this window starts, or nil if it never does (no
  /// days, or zero length). Looks a week ahead, which is as far as a weekly window can be.
  func nextStart(after date: Date, calendar: Calendar) -> Date? {
    guard start != end, !days.isEmpty else { return nil }
    let today = calendar.startOfDay(for: date)
    for offset in 0...7 {
      guard let day = calendar.date(byAdding: .day, value: offset, to: today),
        days.contains(calendar.component(.weekday, from: day)),
        let candidate = calendar.date(byAdding: .minute, value: start, to: day), candidate > date else { continue }
      return candidate
    }
    return nil
  }
}

/// The whole schedule: any number of windows, and whether it's switched on at all. Stored in
/// defaults as JSON, with the switch its own key so the rows survive being turned off.
struct Schedule: Equatable, Codable {
  var windows: [ScheduleWindow] = []

  static let windowsKey = "scheduleWindows"
  static let enabledKey = "scheduledArmingEnabled"

  func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
    return windows.contains { $0.contains(date, calendar: calendar) }
  }

  /// The latest end among the windows containing `date`: what the popover names as "until".
  /// Overlapping rows just mean armed; the last one to finish is when it stops.
  func end(of date: Date, calendar: Calendar = .current) -> Date? {
    return windows.compactMap { $0.end(of: date, calendar: calendar) }.max()
  }

  /// The earliest start after `date` across the windows: what the popover names as the next
  /// window while unarmed, and what keeps the Mac awake for it (spec 0044). nil when nothing is
  /// ever coming.
  func nextStart(after date: Date, calendar: Calendar = .current) -> Date? {
    return windows.compactMap { $0.nextStart(after: date, calendar: calendar) }.min()
  }

  static func load(from defaults: UserDefaults) -> Schedule {
    guard let data = defaults.data(forKey: windowsKey),
      let schedule = try? JSONDecoder().decode(Schedule.self, from: data) else {
      return Schedule()
    }
    return schedule
  }

  func save(to defaults: UserDefaults) {
    if let data = try? JSONEncoder().encode(self) {
      defaults.set(data, forKey: Schedule.windowsKey)
    }
  }

  static func isEnabled(in defaults: UserDefaults) -> Bool {
    return defaults.bool(forKey: enabledKey)
  }

  /// What the schedule wants done at this moment, from the change since the last look rather
  /// than the state itself (spec 0038). Entering a window arms; leaving one disarms only what the
  /// schedule armed; nothing in between, so a manual disarm inside a window holds until the next
  /// window starts, and a manual arm outside one is never touched. `insideBefore` is nil on the
  /// first look after launch or a change to the schedule, and a window already under way then
  /// counts as entered.
  enum Action: Equatable {
    case none, arm, disarm
  }

  static func action(enabled: Bool, insideNow: Bool, insideBefore: Bool?, state: RecordingManager.ArmState,
                     armedBySchedule: Bool, canFire: Bool) -> Action {
    guard enabled else { return .none }
    let entered = insideNow && insideBefore != true
    let left = !insideNow && insideBefore == true
    if entered {
      return state == .unarmed && canFire ? .arm : .none
    }
    if left {
      return armedBySchedule && state != .unarmed ? .disarm : .none
    }
    return .none
  }
}
