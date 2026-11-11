//
//  ArmedRecord.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/23/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import Foundation

/// A trace of being armed that outlives the process (spec 0045). Written when arming starts,
/// refreshed on the minute while armed, removed by a disarm and by a normal quit. Found at launch,
/// it means the previous run ended without either: a crash, a force quit, a power cut. What it
/// holds is the last moment OnCue was known to be armed and whether the schedule armed it.
struct ArmedRecord: Equatable {
  static let lastSeenKey = "armedRecordLastSeen"
  static let byScheduleKey = "armedRecordBySchedule"

  let lastSeen: Date
  let bySchedule: Bool

  static func read(from defaults: UserDefaults) -> ArmedRecord? {
    guard let lastSeen = defaults.object(forKey: lastSeenKey) as? Date else { return nil }
    return ArmedRecord(lastSeen: lastSeen, bySchedule: defaults.bool(forKey: byScheduleKey))
  }

  func write(to defaults: UserDefaults) {
    defaults.set(lastSeen, forKey: ArmedRecord.lastSeenKey)
    defaults.set(bySchedule, forKey: ArmedRecord.byScheduleKey)
  }

  static func clear(in defaults: UserDefaults) {
    defaults.removeObject(forKey: lastSeenKey)
    defaults.removeObject(forKey: byScheduleKey)
  }

  /// What a launch does with a record the previous run left behind.
  struct Recovery: Equatable {
    /// Arm again, with the launch countdown. False only when the schedule had armed it and the
    /// launch is outside every window: that window has ended, and the schedule's own rule holds.
    let rearm: Bool
    /// Carried over so a window's end still disarms what the schedule armed.
    let bySchedule: Bool
    /// When OnCue was last known to be watching; the gap runs from here to the launch.
    let gapStart: Date
  }

  static func recovery(from record: ArmedRecord?, insideWindowNow: Bool) -> Recovery? {
    guard let record = record else { return nil }
    let rearm = !record.bySchedule || insideWindowNow
    return Recovery(rearm: rearm, bySchedule: record.bySchedule && rearm, gapStart: record.lastSeen)
  }
}
