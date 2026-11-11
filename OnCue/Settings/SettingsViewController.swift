//
//  SettingsViewController.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 2/15/20.
//  Copyright © 2020 Jake Van Alstyne
//

import Cocoa
import AVFoundation
import ServiceManagement

class SettingsViewController: NSViewController, CaptureManagerSettingsDelegate, NSTextFieldDelegate {
  @IBOutlet weak private var cameraSelectPopup: NSPopUpButton!
  @IBOutlet weak private var secondCameraSelectPopup: NSPopUpButton!
  @IBOutlet weak private var microphoneSelectPopup: NSPopUpButton!
  // Not bound to the defaults: a binding runs its own validation and shows macOS's generic alert
  // on top of the range message below, so these are loaded and saved here instead.
  @IBOutlet weak private var recordingsFolderField: NSTextField!
  @IBOutlet weak private var recordingsFolderNote: NSTextField!
  @IBOutlet weak private var openAtLoginCheckbox: NSButton!
  @IBOutlet weak private var armAtLoginCheckbox: NSButton!
  @IBOutlet weak private var timeoutField: NSTextField!
  @IBOutlet weak private var preRollField: NSTextField!
  @IBOutlet weak private var recordingsLimitField: NSTextField!
  @IBOutlet weak private var cameraLabel: NSTextField!
  @IBOutlet weak private var secondCameraLabel: NSTextField!
  @IBOutlet weak private var microphoneLabel: NSTextField!
  @IBOutlet weak private var timeoutLabel: NSTextField!
  @IBOutlet weak private var preRollLabel: NSTextField!
  @IBOutlet weak private var recordingsLimitLabel: NSTextField!

  /// Menu tags, not saved values. "System default" and "no second camera" are absences of a
  /// choice and save nil; "no camera" and "no microphone" are choices and save `noDevice`, so
  /// their tags have to differ from the two that mean nothing was picked (spec 0028).
  private static let systemInputID = "system-default"
  private static let noCameraID = DevicePreference.noDevice
  private static let noMicrophoneID = DevicePreference.noDevice
  private static let noSecondCameraID = "no-second-camera"

  /// The window controller is reused, so this is the only hook that runs on every open.
  override func viewWillAppear() {
    super.viewWillAppear()
    // Open at Login can have changed in System Settings since the window was last up (spec 0051).
    refreshLoginState()
    showRecordingsFolder()
    // Opening Settings is looking, which is all the fresh-start notice was asking for (spec 0037).
    FreshStart.app.clear()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    // The window takes its size from this, and this comes from the constraints, so the last row
    // ends 20pt above the bottom whatever gets added above it. It used to be a fixed height, and
    // the folder note (spec 0034) hung off the edge.
    buildScheduleControls()
    labelControlsForAccessibility()
    preferredContentSize = view.fittingSize
    reloadCameras()
    reloadSecondCameras()
    reloadMicrophones()
    refreshLoginState()
    armAtLoginCheckbox.state = UserDefaults.standard.bool(forKey: "armAtLogin") ? .on : .off
    showRecordingsFolder()
    timeoutField.integerValue = UserDefaults.standard.integer(forKey: "timeoutValueInSeconds")
    preRollField.integerValue = Int(PreRoll.seconds())
    recordingsLimitField.integerValue = UserDefaults.standard.integer(forKey: "recordingsLimitGB")

    // Keep the lists current as devices come and go while Settings is open.
    for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        self?.reloadCameras()
        self?.reloadSecondCameras()
        self?.reloadMicrophones()
      }
    }
  }

  /// The camera the first picker shows: the chosen one if it's connected, otherwise whatever
  /// capture fell back to. The second camera's list is built against this same answer, so the two
  /// pickers can't end up naming the same camera.
  private func shownFirstCamera() -> AVCaptureDevice? {
    let captureManager = AppDelegate.captureManager
    return DevicePreference.preferred(
      savedID: UserDefaults.standard.string(forKey: "selectedCameraID"),
      available: captureManager.videoCaptureDevices ?? [],
      fallback: captureManager.currentVideoCaptureDevice ?? captureManager.defaultVideoCaptureDevice
    ) { $0.uniqueID }
  }

  /// Lists the connected cameras and "no camera", and selects the chosen one, or the one in use if
  /// the chosen one is gone.
  private func reloadCameras() {
    let cameras = AppDelegate.captureManager.videoCaptureDevices ?? []
    let noneItem = NSMenuItem(title: String(localized: "No camera", comment: "Camera menu"), action: nil, keyEquivalent: "")
    noneItem.representedObject = SettingsViewController.noCameraID
    cameraSelectPopup.menu?.items = cameras.map {
      let item = NSMenuItem(title: $0.localizedName, action: nil, keyEquivalent: "")
      item.representedObject = $0.uniqueID
      return item
    } + [noneItem]

    let item = cameraSelectPopup.menu?.items.first { $0.representedObject as? String == shownFirstCamera()?.uniqueID }
    cameraSelectPopup.select(item ?? noneItem)
  }

  /// Lists "no second camera", then the connected cameras other than the first, and selects the
  /// chosen second camera if it's connected, otherwise none.
  private func reloadSecondCameras() {
    let firstID = shownFirstCamera()?.uniqueID
    let cameras = DevicePreference.secondChoices(
      available: AppDelegate.captureManager.videoCaptureDevices ?? [], firstID: firstID) { $0.uniqueID }
    let noneItem = NSMenuItem(title: String(localized: "No second camera", comment: "Second camera menu"), action: nil, keyEquivalent: "")
    noneItem.representedObject = SettingsViewController.noSecondCameraID
    secondCameraSelectPopup.menu?.items = [noneItem] + cameras.map {
      let item = NSMenuItem(title: $0.localizedName, action: nil, keyEquivalent: "")
      item.representedObject = $0.uniqueID
      return item
    }

    // The same rule capture uses, so the window can't claim a second camera the app is ignoring.
    let second = DevicePreference.second(
      savedID: UserDefaults.standard.string(forKey: "secondCameraID"),
      available: cameras, firstID: firstID) { $0.uniqueID }
    let item = secondCameraSelectPopup.menu?.items.first { $0.representedObject as? String == second?.uniqueID } ?? noneItem
    secondCameraSelectPopup.select(item)
  }

  @IBAction func handleSecondCameraSelection(_ popUpButton: NSPopUpButton) {
    guard let id = popUpButton.selectedItem?.representedObject as? String else { return }
    if id == SettingsViewController.noSecondCameraID {
      AppDelegate.captureManager.changeSecondVideoCaptureDevice(nil)
      return
    }
    // The camera may have been disconnected since the menu was built.
    guard let device = AppDelegate.captureManager.videoCaptureDevices.first(where: { $0.uniqueID == id }) else { return }
    AppDelegate.captureManager.changeSecondVideoCaptureDevice(device)
  }

  /// Lists the system-input entry, then the connected mics, and selects the chosen mic if it's
  /// connected, otherwise the system-input entry.
  private func reloadMicrophones() {
    let mics = AppDelegate.captureManager.audioCaptureDevices ?? []
    let systemItem = NSMenuItem(title: String(localized: "System default", comment: "Microphone menu"), action: nil, keyEquivalent: "")
    systemItem.representedObject = SettingsViewController.systemInputID
    let noneItem = NSMenuItem(title: String(localized: "No microphone", comment: "Microphone menu"), action: nil, keyEquivalent: "")
    noneItem.representedObject = SettingsViewController.noMicrophoneID
    microphoneSelectPopup.menu?.items = [systemItem] + mics.map {
      let item = NSMenuItem(title: $0.localizedName, action: nil, keyEquivalent: "")
      item.representedObject = $0.uniqueID
      return item
    } + [noneItem]

    // nil means nothing was picked, which follows the system input; noDevice means none was picked
    // on purpose. Only the second matches an item.
    let selectedID = UserDefaults.standard.string(forKey: "selectedMicrophoneID")
    let item = microphoneSelectPopup.menu?.items.first { $0.representedObject as? String == selectedID } ?? systemItem
    microphoneSelectPopup.select(item)
  }

  @IBAction func handleMicrophoneSelection(_ popUpButton: NSPopUpButton) {
    guard let id = popUpButton.selectedItem?.representedObject as? String else { return }
    if id == SettingsViewController.noMicrophoneID {
      AppDelegate.captureManager.chooseNoAudioCaptureDevice()
      return
    }
    if id == SettingsViewController.systemInputID {
      AppDelegate.captureManager.changeAudioCaptureDevice(nil)
      return
    }
    // The mic may have been disconnected since the menu was built.
    guard let device = AppDelegate.captureManager.audioCaptureDevices.first(where: { $0.uniqueID == id }) else { return }
    AppDelegate.captureManager.changeAudioCaptureDevice(device)
  }

  @IBAction func handleCameraSelection(_ popUpButton: NSPopUpButton) {
    guard let id = popUpButton.selectedItem?.representedObject as? String else { return }
    if id == SettingsViewController.noCameraID {
      // Capture clears the second camera too, since a single camera is always the first one.
      AppDelegate.captureManager.changeVideoCaptureDevice(nil)
      reloadSecondCameras()
      return
    }
    // The camera may have been disconnected since the menu was built.
    guard let device = AppDelegate.captureManager.videoCaptureDevices.first(where: { $0.uniqueID == id }) else { return }
    AppDelegate.captureManager.changeVideoCaptureDevice(device)
    // The second camera can't be the first, so its list changes with it.
    reloadSecondCameras()
  }

  /// Saves a number field once its value passed the formatter's range. An empty field passes the
  /// formatter but isn't a value, and would otherwise save as 0, so it goes back to its default.
  func controlTextDidEndEditing(_ notification: Notification) {
    guard let field = notification.object as? NSTextField, let setting = fieldDefault(field) else { return }
    if field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
      field.integerValue = setting.value
    }
    UserDefaults.standard.set(field.integerValue, forKey: setting.key)
  }

  /// Arming itself after every launch (spec 0018). Off unless deliberately turned on.
  @IBAction func handleArmAtLogin(_ checkbox: NSButton) {
    UserDefaults.standard.set(checkbox.state == .on, forKey: "armAtLogin")
  }

  // MARK: - Recordings folder (spec 0017)

  /// Shows where recordings go, and what's wrong when something is (spec 0034).
  ///
  /// Called from `viewWillAppear` as well as here, because the settings window controller is built
  /// once and reused: `viewDidLoad` runs on the first open of a session and never again, so
  /// ejecting a drive left this naming it through a close and reopen while recordings were going
  /// somewhere else entirely.
  private func showRecordingsFolder() {
    let current = RecordingsFolder.current()
    let state = RecordingsFolder.state(chosen: RecordingsFolder.resolveChosen(),
                                       inUse: current.folder,
                                       isFallback: current.isFallback,
                                       writable: RecordingsFolder.canWrite(to: current.folder))
    recordingsFolderField.stringValue = RecordingsFolder.shortPath(current.folder)
    recordingsFolderNote.stringValue = RecordingsFolder.note(for: state)
    // The same line carries the label and the warning, so its colour has to say which it is.
    recordingsFolderNote.textColor = RecordingsFolder.isWarning(state) ? .systemOrange : .secondaryLabelColor
  }

  /// Whether the note is telling you something is wrong, as opposed to saying what the path is.
  static func isWarning(_ state: RecordingsFolder.FolderState) -> Bool {
    switch state {
    case .inUse: return false
    case .fellBack, .notWritable: return true
    }
  }

  @IBAction func handleChooseFolder(_ sender: NSButton) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = RecordingsFolder.current().folder
    panel.prompt = String(localized: "Choose", comment: "Folder panel button")
    panel.message = String(localized: "Choose where OnCue saves its recordings.", comment: "Folder panel message")
    let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
      guard response == .OK, let url = panel.url else { return }
      // Found out by writing, at the one moment someone is standing here able to pick somewhere
      // else. Accepting a folder OnCue has just proven it can't use means arming into a failure
      // that surfaces later, to whoever has walked away (spec 0034).
      guard RecordingsFolder.canWrite(to: url) else {
        self?.sayCannotWrite(to: url)
        return
      }
      RecordingsFolder.choose(url)
      AppDelegate.recordingManager.recordingsFolderChanged()
      self?.showRecordingsFolder()
    }
    if let window = view.window {
      panel.beginSheetModal(for: window, completionHandler: finish)
    } else {
      finish(panel.runModal())
    }
  }

  /// The chosen folder is left as it was, so a refused attempt doesn't dump anyone back to the
  /// default. It says OnCue can't write there without guessing why: it can't tell Time Machine
  /// protection from ownership from a read-only mount, and calling a working backup disk broken
  /// would be worse than saying nothing.
  private func sayCannotWrite(to url: URL) {
    let alert = NSAlert()
    alert.messageText = String(localized: "OnCue can't write to \(RecordingsFolder.shortPath(url))", comment: "Alert title; the argument is a folder path")
    alert.informativeText = String(localized: "Recordings are still going where they were. Some folders don't allow it, including Time Machine disks and anything read-only.", comment: "Alert text when a chosen folder can't be written")
    alert.addButton(withTitle: String(localized: "OK", comment: "Alert button"))
    present(alert)
  }

  /// Back to ~/Movies/OnCue. Recordings already written stay where they are.
  @IBAction func handleResetFolder(_ sender: NSButton) {
    RecordingsFolder.reset()
    AppDelegate.recordingManager.recordingsFolderChanged()
    showRecordingsFolder()
  }

  // MARK: - Accessibility (spec 0049)

  /// The label beside each control is its name for a screen reader; nothing in the storyboard
  /// tied them together, so a pop-up read as its selected item and a field as a bare number.
  private func labelControlsForAccessibility() {
    cameraSelectPopup.setAccessibilityTitleUIElement(cameraLabel)
    secondCameraSelectPopup.setAccessibilityTitleUIElement(secondCameraLabel)
    microphoneSelectPopup.setAccessibilityTitleUIElement(microphoneLabel)
    timeoutField.setAccessibilityTitleUIElement(timeoutLabel)
    preRollField.setAccessibilityTitleUIElement(preRollLabel)
    recordingsLimitField.setAccessibilityTitleUIElement(recordingsLimitLabel)
    recordingsFolderField.setAccessibilityLabel(String(localized: "Recordings folder", comment: "Accessibility label, Settings path field"))
  }

  // MARK: - Open at login (spec 0015)

  /// The login item's state as last read. Asking macOS is a synchronous call that can take
  /// seconds, so it's read once when the window appears, off the main thread, and after each
  /// change made here; the schedule note uses this rather than asking again (spec 0051).
  private var loginState: LoginItem.State = .on

  private func refreshLoginState() {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let state = LoginItem.app.state
      DispatchQueue.main.async {
        guard let self = self else { return }
        self.loginState = state
        self.showOpenAtLogin(state)
        self.updateScheduleNote()
      }
    }
  }

  /// macOS's login items are the record, so the checkbox shows their state. One switched off in
  /// System Settings comes back as needing approval, and shows unchecked.
  private func showOpenAtLogin(_ state: LoginItem.State) {
    openAtLoginCheckbox.state = LoginItem.isChecked(state) ? .on : .off
  }

  /// Checking the box asks macOS to open OnCue at login; if macOS still needs the user's approval
  /// (it was switched off in System Settings), offer to open Login Items.
  @IBAction func handleOpenAtLogin(_ checkbox: NSButton) {
    let result = LoginItem.app.set(checkbox.state == .on)
    loginState = result.state
    showOpenAtLogin(result.state)
    updateScheduleNote()
    NotificationCenter.default.post(name: LoginItem.stateChanged, object: nil,
                                    userInfo: [LoginItem.stateKey: result.state])
    if let error = result.error {
      let alert = NSAlert()
      alert.messageText = String(localized: "OnCue couldn't change whether it opens at login.", comment: "Alert title")
      alert.informativeText = error.localizedDescription
      present(alert)
    } else if result.state == .needsApproval {
      askForLoginApproval()
    }
  }

  private func askForLoginApproval() {
    let alert = NSAlert()
    alert.messageText = String(localized: "macOS needs your approval before OnCue can open at login.", comment: "Alert title")
    alert.informativeText = String(localized: "Turn on OnCue in System Settings, under General > Login Items.", comment: "Alert text")
    alert.addButton(withTitle: String(localized: "Open Login Items", comment: "Alert button"))
    alert.addButton(withTitle: String(localized: "Not Now", comment: "Alert button"))
    present(alert) { response in
      if response == .alertFirstButtonReturn {
        SMAppService.openSystemSettingsLoginItems()
      }
    }
  }

  private func present(_ alert: NSAlert, then handler: ((NSApplication.ModalResponse) -> Void)? = nil) {
    if let window = view.window {
      alert.beginSheetModal(for: window) { handler?($0) }
    } else {
      handler?(alert.runModal())
    }
  }

  /// The value each number field goes back to after an invalid entry, and its saved setting.
  private func fieldDefault(_ field: NSTextField) -> (value: Int, key: String)? {
    if field === timeoutField { return (5, "timeoutValueInSeconds") }
    if field === preRollField { return (5, "preRollSeconds") }
    // 0 is a real value here, not a fallback: it means keep everything (spec 0029).
    if field === recordingsLimitField { return (0, "recordingsLimitGB") }
    return nil
  }

  /// A number field's value was out of range. macOS's own alert only says "Please provide a valid
  /// value", so say what the range is instead, taken from the field's formatter, and put the field
  /// back to its default rather than leave it holding the rejected entry.
  func control(_ control: NSControl, didFailToFormatString string: String, errorDescription error: String?) -> Bool {
    guard let field = control as? NSTextField, let formatter = field.formatter as? NumberFormatter,
      let minimum = formatter.minimum, let maximum = formatter.maximum else { return false }
    if let reset = fieldDefault(field) {
      // After this call returns, so the field editor lets go of the rejected text first.
      DispatchQueue.main.async {
        field.abortEditing()
        field.integerValue = reset.value
        UserDefaults.standard.set(reset.value, forKey: reset.key)
      }
    }
    let alert = NSAlert()
    alert.messageText = String(localized: "Enter a number from \(minimum.stringValue) to \(maximum.stringValue).", comment: "Alert title; the arguments are the allowed minimum and maximum")
    if let window = view.window {
      alert.beginSheetModal(for: window)
    } else {
      alert.runModal()
    }
    return false
  }
  // MARK: - Arming on a schedule (spec 0038)

  private let scheduleCheckbox = NSButton(checkboxWithTitle: String(localized: "Watch on a schedule", comment: "Settings checkbox"), target: nil, action: nil)
  private let scheduleRows = NSStackView()
  private let addWindowButton = NSButton(title: String(localized: "Add a window", comment: "Settings button adding a schedule row"), target: nil, action: nil)
  private let scheduleNote = NSTextField(wrappingLabelWithString:
    String(localized: "The schedule only runs while OnCue is open, so turn on Open OnCue at Login. While the schedule is on, OnCue keeps the Mac awake the whole time, on days without a window too.", comment: "Settings note under the schedule"))
  private var schedule = Schedule()

  /// Built in code rather than the storyboard: the rows come and go with the schedule, and the
  /// view's bottom moves from the folder note to this section so the window grows with it.
  private func buildScheduleControls() {
    schedule = Schedule.load(from: UserDefaults.standard)
    scheduleCheckbox.state = Schedule.isEnabled(in: UserDefaults.standard) ? .on : .off
    scheduleCheckbox.target = self
    scheduleCheckbox.action = #selector(scheduleEnabledChanged(_:))
    addWindowButton.target = self
    addWindowButton.action = #selector(addScheduleWindow(_:))
    addWindowButton.bezelStyle = .rounded
    scheduleNote.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    scheduleNote.textColor = .secondaryLabelColor
    scheduleRows.orientation = .vertical
    scheduleRows.alignment = .leading
    scheduleRows.spacing = 6

    let section = NSStackView(views: [scheduleCheckbox, scheduleRows, addWindowButton, scheduleNote])
    section.orientation = .vertical
    section.alignment = .leading
    section.spacing = 8
    section.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(section)

    // The storyboard pins the view's bottom to the folder note (0034); this section now sits
    // under the note and takes that pin over.
    view.constraints.first { $0.firstAttribute == .bottom && $0.secondItem === recordingsFolderNote }?.isActive = false
    NSLayoutConstraint.activate([
      section.topAnchor.constraint(equalTo: recordingsFolderNote.bottomAnchor, constant: 16),
      section.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      section.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      view.bottomAnchor.constraint(equalTo: section.bottomAnchor, constant: 20),
      scheduleNote.widthAnchor.constraint(equalTo: section.widthAnchor),
    ])
    rebuildScheduleRows()
  }

  /// The note under the schedule: grey and informative, or orange and a warning when the
  /// schedule can't arm after a restart because OnCue won't open at login (spec 0051). Never
  /// touches the login item itself.
  private func updateScheduleNote() {
    if ScheduleRisk.scheduleOnly(loginState: loginState) {
      scheduleNote.stringValue = String(localized: "The schedule only arms OnCue while it's open, and with Open OnCue at Login off nothing opens it after a restart. Turn it on above, or open OnCue yourself after each restart.", comment: "Settings warning under the schedule")
      scheduleNote.textColor = .systemOrange
    } else if loginState == .on {
      // Open at Login is on: nothing left to ask for, so only the sleep sentence remains.
      scheduleNote.stringValue = String(localized: "While the schedule is on, OnCue keeps the Mac awake the whole time, including days without a window.", comment: "Settings note under the schedule, Open at Login already on")
      scheduleNote.textColor = .secondaryLabelColor
    } else {
      scheduleNote.stringValue = String(localized: "The schedule only runs while OnCue is open, so turn on Open OnCue at Login. While the schedule is on, OnCue keeps the Mac awake the whole time, on days without a window too.", comment: "Settings note under the schedule")
      scheduleNote.textColor = .secondaryLabelColor
    }
  }

  private func rebuildScheduleRows() {
    scheduleRows.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for (index, window) in schedule.windows.enumerated() {
      scheduleRows.addArrangedSubview(ScheduleRowView(window: window, enabled: scheduleCheckbox.state == .on) { [weak self] changed in
        self?.updateScheduleWindow(at: index, to: changed)
      } onRemove: { [weak self] in
        self?.removeScheduleWindow(at: index)
      })
    }
    scheduleRows.isHidden = schedule.windows.isEmpty
    updateScheduleNote()
    // The window is sized from the view once, at load; after that it has to be told.
    preferredContentSize = view.fittingSize
    view.window?.setContentSize(view.fittingSize)
  }

  @objc private func scheduleEnabledChanged(_ checkbox: NSButton) {
    UserDefaults.standard.set(checkbox.state == .on, forKey: Schedule.enabledKey)
    updateScheduleNote()
    rebuildScheduleRows()
  }

  @objc private func addScheduleWindow(_ sender: Any?) {
    // Weekdays, nine to five: the row most people will edit rather than build.
    schedule.windows.append(ScheduleWindow(days: [2, 3, 4, 5, 6], start: 9 * 60, end: 17 * 60))
    schedule.save(to: UserDefaults.standard)
    rebuildScheduleRows()
  }

  private func updateScheduleWindow(at index: Int, to window: ScheduleWindow) {
    guard schedule.windows.indices.contains(index) else { return }
    schedule.windows[index] = window
    schedule.save(to: UserDefaults.standard)
  }

  private func removeScheduleWindow(at index: Int) {
    guard schedule.windows.indices.contains(index) else { return }
    schedule.windows.remove(at: index)
    schedule.save(to: UserDefaults.standard)
    rebuildScheduleRows()
  }
}

/// One window of the schedule: seven day toggles, a start time, an end time, and a remove button.
private class ScheduleRowView: NSStackView {
  private var scheduleWindow: ScheduleWindow
  private let onChange: (ScheduleWindow) -> Void
  private let onRemove: () -> Void
  private var dayButtons: [NSButton] = []
  private let startPicker = NSDatePicker()
  private let endPicker = NSDatePicker()
  /// Shown when the end is earlier than the start: the window crosses midnight and ends tomorrow.
  private let nextDayLabel = NSTextField(labelWithString: String(localized: "next day", comment: "Schedule row, after an end time earlier than the start"))

  init(window: ScheduleWindow, enabled: Bool, onChange: @escaping (ScheduleWindow) -> Void, onRemove: @escaping () -> Void) {
    self.scheduleWindow = window
    self.onChange = onChange
    self.onRemove = onRemove
    super.init(frame: .zero)
    orientation = .horizontal
    spacing = 6
    // Calendar weekday numbers: 1 is Sunday. The symbols come from the calendar, so they're
    // already in the user's language and order-independent of ours.
    let symbols = Calendar.current.veryShortWeekdaySymbols
    let names = Calendar.current.weekdaySymbols
    for weekday in 1...7 {
      let button = NSButton(checkboxWithTitle: symbols[weekday - 1], target: self, action: #selector(dayToggled(_:)))
      button.tag = weekday
      // One letter on screen, the whole day for a reader (spec 0049); both from the calendar.
      button.setAccessibilityLabel(names[weekday - 1])
      button.state = window.days.contains(weekday) ? .on : .off
      button.isEnabled = enabled
      dayButtons.append(button)
      addArrangedSubview(button)
    }
    for (picker, minutes, action) in [(startPicker, window.start, #selector(startChanged(_:))), (endPicker, window.end, #selector(endChanged(_:)))] {
      picker.datePickerStyle = .textField
      picker.datePickerElements = .hourMinute
      picker.dateValue = Calendar.current.date(byAdding: .minute, value: minutes, to: Calendar.current.startOfDay(for: Date())) ?? Date()
      picker.target = self
      picker.action = action
      picker.isEnabled = enabled
    }
    startPicker.setAccessibilityLabel(String(localized: "Start time", comment: "Accessibility label, schedule row"))
    endPicker.setAccessibilityLabel(String(localized: "End time", comment: "Accessibility label, schedule row"))
    let to = NSTextField(labelWithString: String(localized: "to", comment: "Schedule row, between the start and end times"))
    to.textColor = .secondaryLabelColor
    nextDayLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    nextDayLabel.textColor = .secondaryLabelColor
    let remove = NSButton(title: "", image: NSImage(named: NSImage.removeTemplateName) ?? NSImage(), target: self, action: #selector(removeTapped(_:)))
    remove.bezelStyle = .smallSquare
    remove.imagePosition = .imageOnly
    remove.isEnabled = enabled
    remove.setAccessibilityLabel(String(localized: "Remove this window", comment: "Accessibility label, schedule row minus button"))
    for control in [startPicker, to, endPicker, nextDayLabel, remove] as [NSView] {
      addArrangedSubview(control)
    }
    showCrossing()
  }

  private func showCrossing() {
    nextDayLabel.isHidden = !(scheduleWindow.end < scheduleWindow.start)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private static func minutes(of picker: NSDatePicker) -> Int {
    let parts = Calendar.current.dateComponents([.hour, .minute], from: picker.dateValue)
    return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
  }

  @objc private func dayToggled(_ button: NSButton) {
    if button.state == .on { scheduleWindow.days.insert(button.tag) } else { scheduleWindow.days.remove(button.tag) }
    onChange(scheduleWindow)
  }

  @objc private func startChanged(_ picker: NSDatePicker) {
    scheduleWindow.start = ScheduleRowView.minutes(of: picker)
    showCrossing()
    onChange(scheduleWindow)
  }

  @objc private func endChanged(_ picker: NSDatePicker) {
    scheduleWindow.end = ScheduleRowView.minutes(of: picker)
    showCrossing()
    onChange(scheduleWindow)
  }

  @objc private func removeTapped(_ sender: Any?) {
    onRemove()
  }
}
