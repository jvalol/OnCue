//
//  OnCueIntents.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/23/26.
//  Copyright © 2026 Jake Van Alstyne
//

import AppIntents
import Foundation

/// Where the intents find the manager (spec 0050). The app points this at its own at launch;
/// the tests point it at theirs. Nil means OnCue hasn't finished launching, which the system
/// waits for before performing an intent, so it's an error the user never sees.
enum IntentTargets {
  static var manager: (() -> RecordingManager)?

  @MainActor static func requireManager() throws -> RecordingManager {
    guard let manager = manager?() else { throw IntentError.notReady }
    return manager
  }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
  case notReady
  var localizedStringResource: LocalizedStringResource {
    LocalizedStringResource("OnCue isn't running yet.", comment: "Intent error")
  }
}

/// Arm, the way the popover's Arm does: a person asked, so five seconds and no notification.
struct ArmIntent: AppIntent {
  static var title: LocalizedStringResource = LocalizedStringResource("Arm OnCue", comment: "Shortcuts action")
  static var description = IntentDescription(LocalizedStringResource("Arms OnCue after a short countdown, so it records when it sees motion or hears sound.", comment: "Shortcuts action description"))
  static var openAppWhenRun = false

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    IntentTrace.note("ArmIntent performed")
    let manager = try IntentTargets.requireManager()
    guard manager.state() == .unarmed else {
      return .result(dialog: IntentDialog(LocalizedStringResource("OnCue is already armed.", comment: "Shortcuts result")))
    }
    guard manager.canArm() else {
      return .result(dialog: IntentDialog(LocalizedStringResource("OnCue can't arm: nothing can trigger a recording. Check the camera and microphone in Preferences.", comment: "Shortcuts result")))
    }
    manager.startArming(countdown: 5)
    return .result(dialog: IntentDialog(LocalizedStringResource("OnCue is arming.", comment: "Shortcuts result")))
  }
}

struct DisarmIntent: AppIntent {
  static var title: LocalizedStringResource = LocalizedStringResource("Disarm OnCue", comment: "Shortcuts action")
  static var description = IntentDescription(LocalizedStringResource("Stops OnCue watching, whatever armed it.", comment: "Shortcuts action description"))
  static var openAppWhenRun = false

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    IntentTrace.note("DisarmIntent performed")
    let manager = try IntentTargets.requireManager()
    manager.disarm()
    return .result(dialog: IntentDialog(LocalizedStringResource("OnCue is disarmed.", comment: "Shortcuts result")))
  }
}

/// True for arming, armed and recording; the state line as the spoken answer.
struct IsArmedIntent: AppIntent {
  static var title: LocalizedStringResource = LocalizedStringResource("Is OnCue Armed", comment: "Shortcuts action")
  static var description = IntentDescription(LocalizedStringResource("Whether OnCue is watching right now, for an If, and what its state is.", comment: "Shortcuts action description"))
  static var openAppWhenRun = false

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
    IntentTrace.note("IsArmedIntent performed")
    let manager = try IntentTargets.requireManager()
    let armed = manager.state() != .unarmed
    return .result(value: armed, dialog: IntentDialog(stringLiteral: manager.armedStateDescription))
  }
}

struct RecordTestIntent: AppIntent {
  static var title: LocalizedStringResource = LocalizedStringResource("Record a Test", comment: "Popover menu")
  static var description = IntentDescription(LocalizedStringResource("Records a test on every camera, the way a trigger would, and shows the file.", comment: "Shortcuts action description"))
  static var openAppWhenRun = false

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    IntentTrace.note("RecordTestIntent performed")
    let manager = try IntentTargets.requireManager()
    guard RecordingManager.canRecordTest(state: manager.state(), canArm: manager.canArm()), !manager.isRecordingTest else {
      return .result(dialog: IntentDialog(LocalizedStringResource("OnCue can't record a test right now.", comment: "Shortcuts result")))
    }
    manager.recordTest()
    return .result(dialog: IntentDialog(LocalizedStringResource("OnCue is recording a test.", comment: "Shortcuts result")))
  }
}

/// A Focus carries one switch: armed while it's on. The system performs this when such a Focus
/// becomes active, and again with the defaults when it ends (spec 0050).
struct ArmFocusFilter: SetFocusFilterIntent {
  static var title: LocalizedStringResource = LocalizedStringResource("Arm OnCue", comment: "Shortcuts action")
  static var description = IntentDescription(LocalizedStringResource("Keeps OnCue armed while this Focus is on.", comment: "Focus Filter description"))

  @Parameter(title: LocalizedStringResource("Armed while this Focus is on", comment: "Focus Filter switch"), default: false)
  var armed: Bool

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: armed
      ? LocalizedStringResource("Armed", comment: "Focus Filter summary")
      : LocalizedStringResource("Not armed", comment: "Focus Filter summary"))
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    IntentTrace.note("focus filter performed, armed=\(armed), manager=\(IntentTargets.manager != nil)")
    let manager = try IntentTargets.requireManager()
    manager.focusChanged(wantsArmed: armed)
    IntentTrace.note("after focusChanged: state=\(manager.state()) armedByFocus=\(manager.armedByFocus)")
    return .result()
  }
}

/// Debug builds only: a line per intent delivery in the recordings folder, for checking whether
/// the system performs a Focus Filter at all (the unified log isn't readable from every shell).
enum IntentTrace {
  static func note(_ line: String) {
    #if DEBUG
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/OnCue/intents.log")
    let stamp = ISO8601DateFormatter().string(from: Date())
    let data = "\(stamp) \(line)\n".data(using: .utf8)!
    if let handle = try? FileHandle(forWritingTo: url) {
      handle.seekToEndOfFile(); handle.write(data); try? handle.close()
    } else {
      try? data.write(to: url)
    }
    #endif
  }
}

/// Siri's phrases. App Shortcuts phrases are localized through their own catalog, which this
/// doesn't add; the phrases are English, the actions' titles and results are not.
struct OnCueShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(intent: ArmIntent(), phrases: ["Arm \(.applicationName)"],
                shortTitle: LocalizedStringResource("Arm", comment: "Popover button"), systemImageName: "video")
    AppShortcut(intent: DisarmIntent(), phrases: ["Disarm \(.applicationName)"],
                shortTitle: LocalizedStringResource("Disarm", comment: "Popover button"), systemImageName: "video.slash")
    AppShortcut(intent: IsArmedIntent(), phrases: ["Is \(.applicationName) armed"],
                shortTitle: LocalizedStringResource("Is it armed", comment: "Shortcuts short title"), systemImageName: "questionmark.circle")
    AppShortcut(intent: RecordTestIntent(), phrases: ["Record a test with \(.applicationName)"],
                shortTitle: LocalizedStringResource("Record a Test", comment: "Popover menu"), systemImageName: "record.circle")
  }
}
