//
//  SleepRisk.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/19/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import Cocoa
import IOKit.ps

enum SleepRisk {
  /// A laptop sleeps when its lid closes unless it's in clamshell mode: on power with an external display.
  static func lidWouldStopWatching(hasLid: Bool, onExternalPower: Bool, hasExternalDisplay: Bool) -> Bool {
    return hasLid && !(onExternalPower && hasExternalDisplay)
  }
}

/// What the popover's notice line shows, if anything.
///
/// Motion detection having stopped comes first, because it is the only one that is still happening
/// rather than already over (spec 0030). Then the things that already happened, most recent first,
/// since they're all the same class of "you have less footage than you think" (specs 0027, 0029).
/// The lid warning is last: it shows armed or not, so it's in view before pressing Arm, but it's a
/// risk that hasn't happened yet.
enum PopoverNotice: Equatable {
  case none
  case lidWouldStopWatching
  case motionDetectionStopped(soundStillWatching: Bool)
  case wasNotWatching(from: Date, to: Date)
  /// The previous run ended while armed, without a disarm or a normal quit (spec 0045).
  case quitUnexpectedly(at: Date, until: Date)
  case recordingFailed(RecordingFailure, count: Int, at: Date)
  case recordingsDeleted(count: Int, at: Date)
  case freshStart
  /// The schedule is on but OnCue won't open at login, so a restart ends it (spec 0051).
  case scheduleCannotSurviveRestart
  /// OnCue was updated and the changelog says what changed (spec 0058).
  case updated(UpdateNotice.Update)

  static func notice(armed: Bool, lidRisk: Bool, gapStart: Date?, gapEnd: Date?,
                     failure: RecordingFailure? = nil, failureCount: Int = 0,
                     failedAt: Date? = nil,
                     deletedCount: Int = 0, deletedAt: Date? = nil,
                     motionStopped: Bool = false, soundCanWatch: Bool = false,
                     freshStart: Bool = false,
                     quitAt: Date? = nil, quitUntil: Date? = nil,
                     scheduleAtRisk: Bool = false,
                     update: UpdateNotice.Update? = nil) -> PopoverNotice {
    // Outranks everything else here, and it's the only one that does. The rest are news about
    // things that have already finished, and this is a problem that is still happening: right now,
    // nothing is watching for motion (spec 0030).
    //
    // Whether sound is covering for it takes the arm state too, not just the trigger and its mic.
    // Unarmed, nothing is watching, and telling someone sound has them covered at the moment they
    // are working out whether they are covered is the one thing this line must not do.
    if motionStopped {
      return .motionDetectionStopped(soundStillWatching: armed && soundCanWatch)
    }
    let gap: PopoverNotice? = {
      guard armed, let start = gapStart, let end = gapEnd else { return nil }
      return .wasNotWatching(from: start, to: end)
    }()
    let failed: PopoverNotice? = {
      guard let failure = failure, let at = failedAt, failureCount > 0 else { return nil }
      return .recordingFailed(failure, count: failureCount, at: at)
    }()

    let deleted: PopoverNotice? = {
      guard let at = deletedAt, deletedCount > 0 else { return nil }
      return .recordingsDeleted(count: deletedCount, at: at)
    }()
    // Shown armed or not: it's news about the last run, and the launch that found it may not
    // have re-armed (spec 0045).
    let quit: PopoverNotice? = {
      guard let at = quitAt, let until = quitUntil else { return nil }
      return .quitUnexpectedly(at: at, until: until)
    }()

    // Three things that already happened, against one risk that hasn't. Among the three, the most
    // recent wins: they're all "you have less footage than you think" (specs 0027, 0029).
    let happened: [(PopoverNotice, Date)] = [
      gap.map { ($0, gapEnd ?? .distantPast) },
      quit.map { ($0, quitUntil ?? .distantPast) },
      failed.map { ($0, failedAt ?? .distantPast) },
      deleted.map { ($0, deletedAt ?? .distantPast) },
    ].compactMap { $0 }
    if let newest = happened.max(by: { $0.1 < $1.1 }) {
      return newest.0
    }
    // Settings are at their defaults and nobody has looked yet (spec 0037). Below anything that
    // went wrong, since those cost footage; above the lid warning, since on a first launch the
    // reset is the thing most likely to be wrong with this Mac's setup.
    if freshStart {
      return .freshStart
    }
    // Information, not a risk: below everything that happened and the fresh start, above the two
    // risks, because it's owed once and a risk is in view every time (spec 0058).
    if let update = update {
      return .updated(update)
    }
    // Two risks that haven't happened. The schedule's first: it's the one fixed in Settings,
    // and it stays wrong until someone does (spec 0051).
    if scheduleAtRisk {
      return .scheduleCannotSurviveRestart
    }
    return lidRisk ? .lidWouldStopWatching : .none
  }
}

/// Watches power and displays and keeps `lidWouldStopWatching` current, for the popover to observe.
class SleepRiskMonitor: NSObject {
  @objc dynamic private(set) var lidWouldStopWatching = false
  private var powerSource: CFRunLoopSource?

  override init() {
    super.init()
    update()
    let context = Unmanaged.passUnretained(self).toOpaque()
    if let source = IOPSNotificationCreateRunLoopSource({ context in
      guard let context = context else { return }
      Unmanaged<SleepRiskMonitor>.fromOpaque(context).takeUnretainedValue().update()
    }, context)?.takeRetainedValue() {
      CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
      powerSource = source
    }
    NotificationCenter.default.addObserver(self, selector: #selector(update),
                                           name: NSApplication.didChangeScreenParametersNotification, object: nil)
  }

  #if DEBUG
  /// For the store's pictures (spec 0057): the lid line on or off, whatever the Mac is.
  func overrideForScreenshot(lidWouldStopWatching risk: Bool) {
    lidWouldStopWatching = risk
  }
  #endif

  @objc private func update() {
    lidWouldStopWatching = SleepRisk.lidWouldStopWatching(hasLid: SleepRiskMonitor.hasInternalBattery(),
                                                         onExternalPower: SleepRiskMonitor.onExternalPower(),
                                                         hasExternalDisplay: SleepRiskMonitor.hasExternalDisplay())
  }

  /// Only laptops have an internal battery, so it stands in for "has a lid".
  private static func hasInternalBattery() -> Bool {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
    return sources.contains { source in
      let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
      return description?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
    }
  }

  private static func onExternalPower() -> Bool {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return false }
    return type == kIOPMACPowerKey
  }

  private static func hasExternalDisplay() -> Bool {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return false }
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return false }
    return displays.contains { CGDisplayIsBuiltin($0) == 0 }
  }
}
