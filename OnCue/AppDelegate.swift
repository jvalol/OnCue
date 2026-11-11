//
//  AppDelegate.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 10/28/18.
//  Copyright © 2018 Jake Van Alstyne
//

import Cocoa
import UserNotifications

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
  var statusItem: NSStatusItem!
  var popover: NSPopover!
  var popoverEventMonitor: PopoverEventMonitor?
  private var armedStateObservation: NSKeyValueObservation?
  private var recordingFailureObservation: NSKeyValueObservation?
  private var quitAlert: NSAlert?

  @objc dynamic static let recordingManager = RecordingManager()
  @objc dynamic static let captureManager = CaptureManager()
  static let sleepRiskMonitor = SleepRiskMonitor()

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    #if DEBUG
    // The store's pictures, drawn by the app (spec 0057): the overrides go in before anything
    // reads defaults, and the drawing happens once the popover exists, below.
    StoreScreenshots.prepareDefaults()
    #endif
    UserDefaults.standard.register(defaults: [
      DetectLaunch.keyforLaunch: true,
      "motionTriggerEnabled": true,
      "audioTriggerEnabled": false,
      "audioTriggerThreshold": 70,
      "preRollSeconds": 5
    ])

    let freshContainer = DetectLaunch.isFirst
    if DetectLaunch.isFirst {
      DetectLaunch.isFirst = false
      UserDefaults.standard.set(50, forKey: "motionTriggerThreshold")
      UserDefaults.standard.set(5, forKey: "timeoutValueInSeconds")
      // An empty container is also what an update across a bundle ID change looks like; say so
      // until someone has looked (spec 0037).
      FreshStart.app.begin()
    }
    // An update owes a line pointing at the changelog (spec 0058); a fresh container is 0037's.
    #if DEBUG
    let drawingPictures = StoreScreenshots.folder != nil || StorePreview.folder != nil
    #else
    let drawingPictures = false
    #endif
    if !drawingPictures {
      UpdateNotice.app.note(running: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                            fresh: freshContainer)
    }

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if let button = statusItem.button {
      button.action = #selector(togglePopover(_:))
    }
    updateMenuBarIcon()
    // Arming itself is easy to miss, so say so (spec 0018).
    AppDelegate.recordingManager.onArmedAtLaunch = {
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
        guard granted else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "OnCue is arming itself", comment: "Notification title when arming at launch")
        content.body = String(localized: "It will start watching in a few seconds. Open OnCue to stop it.", comment: "Notification body when arming at launch")
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "armed-at-launch", content: content, trigger: nil))
      }
    }
    // Shortcuts, Siri and the Focus Filter reach the manager through here (spec 0050).
    IntentTargets.manager = { AppDelegate.recordingManager }
    // A test recording is the trigger's path started by hand, and its file is shown when done (spec 0046).
    AppDelegate.recordingManager.onTestRecordingWanted = {
      AppDelegate.captureManager.recordTestNow()
    }
    AppDelegate.recordingManager.onTestRecordingFinished = { url in
      NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    armedStateObservation = AppDelegate.recordingManager.observe(\.armedStateRaw) { [weak self] manager, _ in
      // Arming means the settings were good enough to arm with, which is the other way of having
      // looked (spec 0037). Cleared here and not inside RecordingManager: that class watches its
      // own defaults for trigger changes and re-checks whether anything can fire, and a write from
      // inside the arm transition would trip that on every arm. Synchronous, so the popover's own
      // observer, which redraws asynchronously, always reads the cleared flag.
      if manager.state() != .unarmed {
        FreshStart.app.clear()
      }
      DispatchQueue.main.async { self?.updateMenuBarIcon() }
    }
    // A failed recording changes the icon without the arm state moving (spec 0027).
    recordingFailureObservation = AppDelegate.recordingManager.observe(\.recordingFailedAt) { [weak self] _, _ in
      DispatchQueue.main.async { self?.updateMenuBarIcon() }
    }

    let popoverController = PopoverViewController.freshController()
    popover = NSPopover()
    popover.contentViewController = popoverController
    popover.delegate = popoverController

    AppDelegate.captureManager.activityDelegate = popoverController

    if UserDefaults.standard.bool(forKey: "openPreviewWindowAtLaunch") {
      popoverController.togglePreviewWindow()
    }

    popoverEventMonitor = PopoverEventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
      if let strongSelf = self, strongSelf.popover.isShown {
        strongSelf.closePopover(sender: event)
      }
    }

    #if DEBUG
    if let folder = StoreScreenshots.folder {
      do {
        try StoreScreenshots.render(into: folder)
        print("store screenshots: written to \(folder.path)")
      } catch {
        print("store screenshots: \(error.localizedDescription)")
      }
      exit(0)
    }
    if let folder = StorePreview.folder {
      do {
        try StorePreview.render(into: folder)
        print("store preview: written to \(folder.path)")
      } catch {
        print("store preview: \(error.localizedDescription)")
        exit(1)
      }
      exit(0)
    }
    #endif
  }

  /// A recording in progress is finalized before quitting: the recorder writes the file's index
  /// last, asynchronously, so quitting straight away leaves a file missing its last seconds. The
  /// wait is shown, with a way out (spec 0019).
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    let manager = AppDelegate.recordingManager
    guard RecordingManager.waitsBeforeQuitting(isRecording: manager.isRecording()) else {
      return .terminateNow
    }

    let alert = NSAlert()
    alert.messageText = String(localized: "Finishing the recording…", comment: "Alert title when quitting mid-recording")
    alert.informativeText = String(localized: "OnCue is writing the last of what it recorded, then it will quit.", comment: "Alert text when quitting mid-recording")
    alert.addButton(withTitle: String(localized: "Quit Now", comment: "Alert button"))
    alert.addButton(withTitle: String(localized: "Keep Recording", comment: "Alert button"))
    quitAlert = alert

    manager.onRecordingsFinished = { [weak self] in
      manager.onRecordingsFinished = nil
      self?.dismissQuitAlert()
      NSApp.reply(toApplicationShouldTerminate: true)
    }
    manager.stopRecording()

    NSApp.activate(ignoringOtherApps: true)
    // Waits as long as the files take; the alert says why and offers a way out.
    let response = alert.runModal()
    quitAlert = nil
    guard manager.onRecordingsFinished != nil else {
      // The files finished while the alert was up, and the reply already went out.
      return .terminateLater
    }
    manager.onRecordingsFinished = nil
    // Quitting now leaves the files as they are; each one opens up to its last index flush.
    NSApp.reply(toApplicationShouldTerminate: response == .alertFirstButtonReturn)
    return .terminateLater
  }

  private func dismissQuitAlert() {
    guard let alert = quitAlert else { return }
    quitAlert = nil
    NSApp.abortModal()
    alert.window.orderOut(nil)
  }

  func applicationWillTerminate(_ aNotification: Notification) {
    DetectLaunch.isFirst = false
    // A quit that got here was a normal one, whether or not it waited for a recording (spec 0045).
    AppDelegate.recordingManager.noteNormalQuit()
  }

  /// The icon's colors show the arm state; its accessibility label names it, in the words the popover
  /// uses. No tooltip: macOS doesn't show one for a menu bar app that isn't active (spec 0014).
  private func updateMenuBarIcon() {
    guard let button = statusItem.button else { return }
    let manager = AppDelegate.recordingManager
    button.image = MenuBarIcon.image(for: MenuBarIcon.appearance(for: manager.state(),
                                                                 recordingFailed: manager.hasRecordingFailure))
    let description = manager.hasRecordingFailure
      ? String(localized: "OnCue - a recording failed", comment: "Menu bar icon accessibility label")
      : String(localized: "OnCue - \(manager.armedStateDescription)", comment: "Menu bar icon accessibility label; the argument is the armed state")
    button.setAccessibilityLabel(description)
  }

  @objc func togglePopover(_ sender: Any?) {
    if popover.isShown {
      closePopover(sender: sender)
    } else {
      showPopover(sender: sender)
    }
  }

  func showPopover(sender: Any?) {
    if let button = statusItem.button {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
    }
    popoverEventMonitor?.start()
  }

  func closePopover(sender: Any?) {
    popover.performClose(sender)
    if !popover.isShown {
      // Delegate might prevent closing if the popover should be floating
      // Keep the event monitor so that the popover can close after unsetting that option
      popoverEventMonitor?.stop()
    }
  }
}

struct DetectLaunch {
  static let keyforLaunch = "validateFirstlaunch"
  static var isFirst: Bool {
    get {
      return UserDefaults.standard.bool(forKey: keyforLaunch)
    }
    set {
      UserDefaults.standard.set(newValue, forKey: keyforLaunch)
    }
  }
}
