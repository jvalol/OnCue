//
//  PopoverMenu.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 2/15/20.
//  Copyright © 2020 Jake Van Alstyne
//

import Cocoa

class PopoverMenu: NSMenu {
  let showRecordingsMenuItem = NSMenuItem(title: String(localized: "Show Recordings", comment: "Popover menu"), action: #selector(showRecordings(_:)), keyEquivalent: "")
  let showWhatHappenedMenuItem = NSMenuItem(title: String(localized: "Show What Happened", comment: "Popover menu"), action: #selector(showWhatHappened(_:)), keyEquivalent: "")
  let makeTimeLapseMenuItem = NSMenuItem(title: String(localized: "Make a Time-lapse", comment: "Popover menu"), action: #selector(makeTimeLapse(_:)), keyEquivalent: "")
  let recordTestMenuItem = NSMenuItem(title: String(localized: "Record a Test", comment: "Popover menu"), action: #selector(recordTest(_:)), keyEquivalent: "")
  let showPrefsMenuItem = NSMenuItem(title: String(localized: "Preferences…", comment: "Popover menu"), action: #selector(showPreferences(_:)), keyEquivalent: "")
  let showAboutMenuItem = NSMenuItem(title: String(localized: "About", comment: "Popover menu"), action: #selector(showAbout(_:)), keyEquivalent: "")
  let quitAppMenuItem = NSMenuItem(title: String(localized: "Quit", comment: "Popover menu"), action: #selector(quitApp(_:)), keyEquivalent: "")

  lazy var settingsWindowController = SettingsWindowController.freshController()
  lazy var settingsViewController = settingsWindowController.contentViewController as? SettingsViewController

  lazy var aboutWindowController = AboutWindowController.freshController()
  lazy var aboutViewController = aboutWindowController.contentViewController as? AboutViewController

  required init(coder: NSCoder) {
    super.init(coder: coder)
  }

  init() {
    super.init(title: "OnCue")

    for menuItem in [showRecordingsMenuItem, showWhatHappenedMenuItem, makeTimeLapseMenuItem, recordTestMenuItem, showPrefsMenuItem, showAboutMenuItem, quitAppMenuItem] {
      menuItem.target = self
    }

    self.addItem(showRecordingsMenuItem)
    self.addItem(showWhatHappenedMenuItem)
    self.addItem(makeTimeLapseMenuItem)
    self.addItem(recordTestMenuItem)
    self.addItem(showPrefsMenuItem)
    self.addItem(showAboutMenuItem)
    self.addItem(NSMenuItem.separator())
    self.addItem(quitAppMenuItem)
  }
}

extension PopoverMenu: NSMenuItemValidation {
  /// Record a Test is offered when Arm would be, or while armed; not mid-countdown or mid-recording
  /// (spec 0046). The other items are always on.
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    let manager = AppDelegate.recordingManager
    if menuItem === showWhatHappenedMenuItem || menuItem === makeTimeLapseMenuItem {
      // Only while a stretch with something in it is remembered (spec 0054), and the title
      // names the stretch, since once armed again nothing else on screen does.
      let happened = manager.whatHappened()
      let span = happened.map { ArmedStretch.spanText($0.stretch) }
      if menuItem === showWhatHappenedMenuItem {
        menuItem.title = span.map { String(localized: "Show What Happened (\($0))", comment: "Popover menu, with the stretch's times") }
          ?? String(localized: "Show What Happened", comment: "Popover menu")
        return happened?.canShow ?? false
      }
      menuItem.title = span.map { String(localized: "Make a Time-lapse (\($0))", comment: "Popover menu, with the stretch's times") }
        ?? String(localized: "Make a Time-lapse", comment: "Popover menu")
      // One at a time (spec 0055).
      return !manager.isMakingTimeLapse && (happened?.canShow ?? false)
    }
    guard menuItem === recordTestMenuItem else { return true }
    return RecordingManager.canRecordTest(state: manager.state(), canArm: manager.canArm()) && !manager.isRecordingTest
  }

  /// The stretch as one short movie in the recordings folder, revealed when done (spec 0055).
  @objc func makeTimeLapse(_ sender: NSMenuItem) {
    let manager = AppDelegate.recordingManager
    guard !manager.isMakingTimeLapse, let happened = manager.whatHappened(), happened.canShow else { return }
    manager.timeLapseStarted()
    // The Settings camera goes on the left when the stretch has two (spec 0056).
    let leftCamera = AppDelegate.captureManager.currentVideoCaptureDevice?.localizedName
    TimeLapseRenderer.make(events: happened.events, stretch: happened.stretch, in: manager.recordingsFolder,
                           leftCamera: leftCamera) { result in
      switch result {
      case .success(let url):
        manager.timeLapseFinished(readable: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
      case .failure(let failure):
        manager.timeLapseFinished(readable: failure != .nothingReadable ? true : false)
        if case .couldNotWrite(let why) = failure {
          print("Time-lapse not written: \(why)")
        }
      }
    }
  }

  /// Finder with the last stretch's files selected, oldest first, stills included (spec 0054).
  @objc func showWhatHappened(_ sender: NSMenuItem) {
    guard let happened = AppDelegate.recordingManager.whatHappened(), !happened.files.isEmpty else { return }
    NSWorkspace.shared.activateFileViewerSelecting(happened.files)
  }

  /// A recording started by hand, to see the whole chain work (spec 0046).
  @objc func recordTest(_ sender: NSMenuItem) {
    AppDelegate.recordingManager.recordTest()
  }

  /// Opens the recordings folder in Finder with the newest recording selected, or just the folder if there are none.
  @objc func showRecordings(_ sender: NSMenuItem) {
    let files = FileOutputManager()
    files.ensureFolderExists()
    if let newest = files.newestRecording() {
      NSWorkspace.shared.activateFileViewerSelecting([newest])
    } else {
      NSWorkspace.shared.open(files.oncuePath)
    }
  }

  @objc func showPreferences(_ sender: NSMenuItem) {
//    AppDelegate.captureManager.settingsDelegate = settingsViewController
    settingsWindowController.showWindow(self)
  }

  @objc func showAbout(_ sender: NSMenuItem) {
    aboutWindowController.showWindow(self)
  }

  @objc func quitApp(_ sender: NSMenuItem) {
    NSApplication.shared.terminate(self)
  }
}
