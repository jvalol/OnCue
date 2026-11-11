//
//  PopoverViewController.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 10/28/18.
//  Copyright © 2018 Jake Van Alstyne
//

import Cocoa
import AVFoundation
import UserNotifications

class PopoverViewController: NSViewController, NSPopoverDelegate {
  @IBOutlet weak private var motionLevelIndicator: NSLevelIndicator!
  @IBOutlet weak private var armedButton: NSButton!
  @IBOutlet weak private var armedTextField: NSTextField!
  @IBOutlet weak private var thresholdSlider: NSSlider!
  @IBOutlet weak private var motionTriggerCheckbox: NSButton!
  @IBOutlet weak private var motionDeviceLabel: NSTextField!
  @IBOutlet weak private var noticeLabel: NSTextField!
  @IBOutlet weak private var soundDeviceLabel: NSTextField!
  @IBOutlet weak private var soundLevelIndicator: NSLevelIndicator!
  @IBOutlet weak private var audioTriggerCheckbox: NSButton!
  @IBOutlet weak private var audioThresholdSlider: NSSlider!
  @IBOutlet weak private var floatButton: NSButton!
  @IBOutlet weak private var menuButton: NSButton!

  @objc dynamic let recordingManager = AppDelegate.recordingManager
  @objc dynamic let captureManager = AppDelegate.captureManager

  var floatPopover: Bool = false
  lazy var previewWindowController = PreviewWindowController.freshController()
  lazy var previewViewController = previewWindowController.contentViewController as? PreviewViewController

  let popoverMenu = PopoverMenu()

  private var armedStateObservation: NSKeyValueObservation?
  private var noticeObservations: [NSKeyValueObservation] = []
  private var previewCloseObserver: NSObjectProtocol?

  var armedCountdownTimer: Timer?
  var countdown: Int = 0

  // The second camera's name, meter, and slider, under the first camera's in the Motion column.
  // Built in code because they only appear while a second camera is set (spec 0012).
  private let secondMotionDeviceLabel = NSTextField(labelWithString: "")
  private let secondMotionLevelIndicator = NSLevelIndicator()
  private let secondThresholdSlider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: nil, action: nil)
  private var armedTextBelowFirstSlider: NSLayoutConstraint?
  private var armedTextBelowSecondSlider: NSLayoutConstraint?
  private var baseContentSize = NSSize.zero

  // Says the screen is lighting the room, when macOS's Edge Light is on (spec 0022). It sits at
  // the bottom of the Motion column, beside the camera that turns it on, rather than in the notice
  // line under the arm state, which belongs to the lid warning and the sleep gap.
  private let edgeLightLabel = NSTextField(wrappingLabelWithString: "")

  // What the trigger has been producing lately (spec 0033). Its own line under the arm state
  // rather than the notice line, which belongs to things that are wrong: a count of recordings is
  // ambient information, and there it would either suppress a real warning or be suppressed by one.
  private let triggerCostLabel = ClickableLabel(wrappingLabelWithString: "")
  private var stretchObservation: NSKeyValueObservation?
  private var timeLapseObservation: NSKeyValueObservation?
  private var loginStateObserver: NSObjectProtocol?
  /// The storyboard's colour for the notice, which the update line changes to a link's.
  private var noticeDefaultColor: NSColor?
  private var triggerCostBelowArmedText: NSLayoutConstraint?
  private var triggerCostBelowNotice: NSLayoutConstraint?
  private var armedButtonBelowNotice: NSLayoutConstraint?
  private var armedButtonBelowTriggerCost: NSLayoutConstraint?
  private var triggerCostShown = false
  /// The stretch's files while the line is showing what happened; empty when it isn't a button.
  private var whatHappenedFiles: [URL] = []
  private var noticeBaseHeight: CGFloat = 0
  /// The login item's state as last read, on until known: asking macOS can take seconds
  /// (spec 0051).
  private var loginState: LoginItem.State = .on
  private var edgeLightBelowFirstSlider: NSLayoutConstraint?
  private var edgeLightBelowSecondSlider: NSLayoutConstraint?
  private var armedTextBelowEdgeLight: NSLayoutConstraint?

  private func buildSecondCameraControls() {
    baseContentSize = view.frame.size
    secondMotionDeviceLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    secondMotionDeviceLabel.textColor = .secondaryLabelColor
    secondMotionDeviceLabel.alignment = .center
    secondMotionDeviceLabel.lineBreakMode = .byTruncatingMiddle
    secondMotionDeviceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    secondMotionLevelIndicator.levelIndicatorStyle = .continuousCapacity
    secondMotionLevelIndicator.maxValue = 100
    secondThresholdSlider.target = self
    secondThresholdSlider.action = #selector(secondThresholdSliderValueChanged(_:))

    for control in [secondMotionDeviceLabel, secondMotionLevelIndicator, secondThresholdSlider] as [NSView] {
      control.translatesAutoresizingMaskIntoConstraints = false
      control.isHidden = true
      view.addSubview(control)
    }
    NSLayoutConstraint.activate([
      secondMotionDeviceLabel.topAnchor.constraint(equalTo: thresholdSlider.bottomAnchor, constant: 8),
      secondMotionDeviceLabel.leadingAnchor.constraint(equalTo: motionLevelIndicator.leadingAnchor),
      secondMotionDeviceLabel.trailingAnchor.constraint(equalTo: motionLevelIndicator.trailingAnchor),
      secondMotionLevelIndicator.topAnchor.constraint(equalTo: secondMotionDeviceLabel.bottomAnchor, constant: 8),
      secondMotionLevelIndicator.leadingAnchor.constraint(equalTo: motionLevelIndicator.leadingAnchor),
      secondMotionLevelIndicator.trailingAnchor.constraint(equalTo: motionLevelIndicator.trailingAnchor),
      secondThresholdSlider.topAnchor.constraint(equalTo: secondMotionLevelIndicator.bottomAnchor, constant: 8),
      secondThresholdSlider.leadingAnchor.constraint(equalTo: thresholdSlider.leadingAnchor),
      secondThresholdSlider.trailingAnchor.constraint(equalTo: thresholdSlider.trailingAnchor),
    ])
    // The arm state hangs below the last slider shown.
    armedTextBelowFirstSlider = view.constraints.first {
      $0.firstItem === armedTextField && $0.firstAttribute == .top && $0.secondItem === thresholdSlider
    }
    armedTextBelowSecondSlider = armedTextField.topAnchor.constraint(equalTo: secondThresholdSlider.bottomAnchor, constant: 8)

    edgeLightLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    edgeLightLabel.textColor = .secondaryLabelColor
    edgeLightLabel.alignment = .center
    edgeLightLabel.translatesAutoresizingMaskIntoConstraints = false
    edgeLightLabel.isHidden = true
    view.addSubview(edgeLightLabel)
    NSLayoutConstraint.activate([
      edgeLightLabel.leadingAnchor.constraint(equalTo: motionLevelIndicator.leadingAnchor),
      edgeLightLabel.trailingAnchor.constraint(equalTo: motionLevelIndicator.trailingAnchor),
    ])
    // Below whichever slider is last, and the arm state below it in turn.
    edgeLightBelowFirstSlider = edgeLightLabel.topAnchor.constraint(equalTo: thresholdSlider.bottomAnchor, constant: 8)
    edgeLightBelowSecondSlider = edgeLightLabel.topAnchor.constraint(equalTo: secondThresholdSlider.bottomAnchor, constant: 8)
    armedTextBelowEdgeLight = armedTextField.topAnchor.constraint(equalTo: edgeLightLabel.bottomAnchor, constant: 8)

    triggerCostLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    triggerCostLabel.textColor = .secondaryLabelColor
    triggerCostLabel.alignment = .center
    triggerCostLabel.translatesAutoresizingMaskIntoConstraints = false
    triggerCostLabel.isHidden = true
    triggerCostLabel.isSelectable = false
    triggerCostLabel.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(showWhatHappened(_:))))
    view.addSubview(triggerCostLabel)
    NSLayoutConstraint.activate([
      triggerCostLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      triggerCostLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
    ])
    // The trigger cost line and the notice line both hang under the arm state, and 4.7 hung them
    // from the same anchor, so whenever both had something to say they drew on top of each other.
    // Now the cost line goes under the notice when there is one, and the Arm button under the cost
    // line whenever it shows; layOutMotionColumn picks which of these are active.
    triggerCostBelowArmedText = triggerCostLabel.topAnchor.constraint(equalTo: armedTextField.bottomAnchor, constant: 8)
    triggerCostBelowNotice = triggerCostLabel.topAnchor.constraint(equalTo: noticeLabel.bottomAnchor, constant: 8)
    armedButtonBelowNotice = view.constraints.first {
      $0.firstItem === armedButton && $0.firstAttribute == .top && $0.secondItem === noticeLabel
    }
    armedButtonBelowTriggerCost = armedButton.topAnchor.constraint(equalTo: triggerCostLabel.bottomAnchor, constant: 8)

    // The notice line wraps (spec 0037). The storyboard has it as one truncating line, which
    // silently cut the end off the longer notices; the height beyond one line is added to the
    // popover in layOutMotionColumn, the same way the trigger cost line is.
    noticeBaseHeight = noticeLabel.frame.height
    noticeDefaultColor = noticeLabel.textColor
    noticeLabel.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(noticeClicked(_:))))
    noticeLabel.lineBreakMode = .byWordWrapping
    noticeLabel.maximumNumberOfLines = 0
  }

  /// Reads the recordings folder, so it runs when the popover opens and when a recording ends,
  /// not on anything repeating.
  /// While unarmed with a stretch remembered, the line answers what happened while OnCue was
  /// armed and is a button to show it in Finder (spec 0054); otherwise it's 0033's cost line.
  private func updateTriggerCost() {
    guard armedTextField != nil else { return }
    if recordingManager.state() == .unarmed, recordingManager.timeLapseFailed {
      // Nothing in the stretch could be read (spec 0055); stays until the popover closes.
      whatHappenedFiles = []
      triggerCostLabel.stringValue = String(localized: "Nothing in that stretch could be read, so no time-lapse was made", comment: "Popover line under the state, after Make a Time-lapse found nothing to use")
      triggerCostLabel.textColor = .secondaryLabelColor
      triggerCostLabel.isClickable = false
      triggerCostShown = true
      layOutMotionColumn()
      return
    }
    if recordingManager.state() == .unarmed, let happened = recordingManager.whatHappened() {
      whatHappenedFiles = happened.files
      triggerCostLabel.stringValue = happened.text
      triggerCostLabel.textColor = whatHappenedFiles.isEmpty ? .secondaryLabelColor : .linkColor
      triggerCostLabel.isClickable = !whatHappenedFiles.isEmpty
      triggerCostShown = true
      layOutMotionColumn()
      return
    }
    whatHappenedFiles = []
    triggerCostLabel.textColor = .secondaryLabelColor
    triggerCostLabel.isClickable = false
    guard let summary = recordingManager.triggerCost() else {
      triggerCostShown = false
      layOutMotionColumn()
      return
    }
    triggerCostLabel.stringValue = summary.text
    triggerCostShown = true
    layOutMotionColumn()
  }

  /// The update line opens the changelog at this version's entry and is then paid (spec 0058).
  @objc private func noticeClicked(_ sender: Any?) {
    guard let update = UpdateNotice.app.pending else { return }
    let running = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    NSWorkspace.shared.open(UpdateNotice.url(for: update, running: running))
    UpdateNotice.app.clear()
    updateNotice()
    closePopover()
  }

  @objc private func showWhatHappened(_ sender: Any?) {
    guard !whatHappenedFiles.isEmpty else { return }
    NSWorkspace.shared.activateFileViewerSelecting(whatHappenedFiles)
    closePopover()
  }

  /// Handing off to another app leaves the popover open with that app's window behind it: the
  /// event monitor only closes it on a click outside, and the browser coming to the front isn't
  /// one. Anything that sends the person to another app closes it on the way out.
  private func closePopover() {
    (NSApp.delegate as? AppDelegate)?.closePopover(sender: self)
  }

  /// A popover is translucent: its background is whatever window is behind it, blurred. Over
  /// the desktop that's fine; over a white page in a browser it goes near-white while the labels
  /// stay the dark mode's white, and the whole thing is unreadable (2026-10-12). The content
  /// view tints itself with the window background colour, most of the way to opaque: the blur
  /// still shows through, which is the look Jake wants kept, and over white the tint pulls the
  /// background far enough towards the labels' own colour to read. The colour is resolved for
  /// the current appearance, so it's set again when that changes.
  private func paintBackground() {
    view.effectiveAppearance.performAsCurrentDrawingAppearance {
      view.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(PopoverViewController.tint).cgColor
    }
  }

  /// How far the popover's background goes towards opaque. At 1 it's a plain window; lower keeps
  /// more of the glass and loses contrast over a light window in the same measure.
  private static let tint: CGFloat = 0.5

  private var appearanceObservation: NSKeyValueObservation?

  private var secondCameraName: String?
  private var edgeLightShown = false

  private func showSecondCamera(named name: String?) {
    secondCameraName = name
    secondMotionDeviceLabel.stringValue = name ?? ""
    if name != nil {
      secondThresholdSlider.doubleValue = MotionDetector.threshold(cameraID: AppDelegate.captureManager.currentSecondVideoCaptureDevice?.uniqueID)
    } else {
      secondMotionLevelIndicator.doubleValue = 0
    }
    layOutMotionColumn()
  }

  /// Cheap enough to call from the meters, which is how the line clears without reopening the
  /// popover: `isEdgeLightActive` is a class property with no practical way to observe it from
  /// Swift, and the meters already report while capture is running.
  private func updateEdgeLightWarning() {
    let captureManager = AppDelegate.captureManager
    let hasCamera = captureManager.currentVideoCaptureDevice != nil || captureManager.currentSecondVideoCaptureDevice != nil
    let warn = EdgeLight.shouldWarn(active: EdgeLight.isActive, hasCamera: hasCamera)
    guard warn != edgeLightShown else { return }
    edgeLightShown = warn
    layOutMotionColumn()
  }

  /// The bottom of the Motion column: the second camera's controls, then the Edge Light line, then
  /// the arm state under whichever of them is last.
  private func layOutMotionColumn() {
    let second = secondCameraName != nil
    for control in [secondMotionDeviceLabel, secondMotionLevelIndicator, secondThresholdSlider] as [NSView] {
      control.isHidden = !second
    }
    edgeLightLabel.stringValue = edgeLightShown ? PopoverViewController.edgeLightText : ""
    edgeLightLabel.isHidden = !edgeLightShown
    triggerCostLabel.isHidden = !triggerCostShown
    let noticeShown = !noticeLabel.stringValue.isEmpty
    triggerCostBelowArmedText?.isActive = triggerCostShown && !noticeShown
    triggerCostBelowNotice?.isActive = triggerCostShown && noticeShown
    armedButtonBelowNotice?.isActive = !triggerCostShown
    armedButtonBelowTriggerCost?.isActive = triggerCostShown

    for constraint in [armedTextBelowFirstSlider, armedTextBelowSecondSlider, armedTextBelowEdgeLight,
                       edgeLightBelowFirstSlider, edgeLightBelowSecondSlider] {
      constraint?.isActive = false
    }
    if edgeLightShown {
      (second ? edgeLightBelowSecondSlider : edgeLightBelowFirstSlider)?.isActive = true
      armedTextBelowEdgeLight?.isActive = true
    } else {
      (second ? armedTextBelowSecondSlider : armedTextBelowFirstSlider)?.isActive = true
    }

    var extra: CGFloat = 0
    if second {
      extra += 8 + secondMotionDeviceLabel.intrinsicContentSize.height
        + 8 + secondMotionLevelIndicator.intrinsicContentSize.height
        + 8 + secondThresholdSlider.intrinsicContentSize.height
    }
    if edgeLightShown {
      extra += 8 + edgeLightHeight()
    }
    // The base size already holds one line of notice; only what wraps past it is extra.
    if noticeShown {
      extra += max(0, labelHeight(noticeLabel, width: baseContentSize.width - 40) - noticeBaseHeight)
    }
    if triggerCostShown {
      let costHeight = labelHeight(triggerCostLabel, width: baseContentSize.width - 32)
      // Under a notice, the cost line is a whole extra row. With no notice it sits where the
      // empty notice row was, so only what it needs beyond that row (its 4pt tighter top, its own
      // height, and the button's 8pt below it) is extra.
      extra += noticeShown ? 8 + costHeight : max(0, costHeight + 4 - noticeBaseHeight)
    }
    preferredContentSize = NSSize(width: baseContentSize.width, height: baseContentSize.height + extra)
  }

  /// The wrapped height of the Edge Light line at the width of the Motion column.
  private func edgeLightHeight() -> CGFloat {
    let width = motionLevelIndicator.frame.width > 0 ? motionLevelIndicator.frame.width : baseContentSize.width / 2 - 24
    return labelHeight(edgeLightLabel, width: width)
  }

  private func labelHeight(_ label: NSTextField, width: CGFloat) -> CGFloat {
    return label.sizeThatFits(NSSize(width: width, height: .greatestFiniteMagnitude)).height
  }

  private static let edgeLightText =
    String(localized: "macOS is lighting the screen to brighten what the camera sees. OnCue can't turn that off.", comment: "Popover notice")

  @objc private func secondThresholdSliderValueChanged(_ sender: NSSlider) {
    MotionDetector.setThreshold(sender.doubleValue, cameraID: AppDelegate.captureManager.currentSecondVideoCaptureDevice?.uniqueID)
    colour(secondMotionLevelIndicator, forThreshold: sender.doubleValue)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.wantsLayer = true
    paintBackground()
    appearanceObservation = view.observe(\.effectiveAppearance) { [weak self] _, _ in self?.paintBackground() }
    buildSecondCameraControls()
    labelControlsForAccessibility()
    armedStateObservation = recordingManager.observe(\.armedStateRaw) { [weak self] _, _ in
      DispatchQueue.main.async {
        self?.updateArmButton()
        self?.updateNotice()
        self?.updateTriggerCost()
      }
    }
    stretchObservation = recordingManager.observe(\.stretchGeneration) { [weak self] _, _ in
      DispatchQueue.main.async { self?.updateTriggerCost() }
    }
    timeLapseObservation = recordingManager.observe(\.timeLapseFailed) { [weak self] _, _ in
      DispatchQueue.main.async { self?.updateTriggerCost() }
    }
    // Settings changing Open at Login while the popover is open (spec 0051): the notice follows
    // the state Settings got back rather than waiting for the next open.
    loginStateObserver = NotificationCenter.default.addObserver(forName: LoginItem.stateChanged, object: nil,
                                                                queue: .main) { [weak self] note in
      guard let state = note.userInfo?[LoginItem.stateKey] as? LoginItem.State else { return }
      self?.loginState = state
      self?.updateNotice()
    }
    noticeObservations = [
      AppDelegate.sleepRiskMonitor.observe(\.lidWouldStopWatching) { [weak self] _, _ in
        DispatchQueue.main.async { self?.updateNotice() }
      },
      recordingManager.observe(\.notWatchingUntil) { [weak self] manager, _ in
        DispatchQueue.main.async {
          self?.updateNotice()
          if let start = manager.notWatchingFrom, let end = manager.notWatchingUntil {
            PopoverViewController.postNotWatchingNotification(from: start, to: end)
          }
        }
      },
      // The schedule changing in Settings can make or clear the restart warning (spec 0051).
      recordingManager.observe(\.scheduleGeneration) { [weak self] _, _ in
        DispatchQueue.main.async { self?.updateNotice() }
      },
      recordingManager.observe(\.quitUnexpectedlyUntil) { [weak self] manager, _ in
        DispatchQueue.main.async {
          self?.updateNotice()
          if let at = manager.quitUnexpectedlyAt, let until = manager.quitUnexpectedlyUntil {
            PopoverViewController.postQuitUnexpectedlyNotification(at: at, until: until)
          }
        }
      },
      // A failed recording changes the line without the arm state or the gap moving (spec 0027).
      recordingManager.observe(\.recordingFailedAt) { [weak self] _, _ in
        DispatchQueue.main.async { self?.updateNotice() }
      },
      recordingManager.observe(\.deletedAt) { [weak self] _, _ in
        DispatchQueue.main.async { self?.updateNotice() }
      },
      // A live problem rather than news, so it changes the line and the Arm button (spec 0030).
      recordingManager.observe(\.motionDetectionStopped) { [weak self] _, _ in
        DispatchQueue.main.async {
          self?.updateNotice()
          self?.updateArmButton()
        }
      },
    ]
    updateNotice()
  }

  /// The line under the arm state: the lid warning while it applies, or when OnCue last wasn't watching.
  private func updateNotice() {
    guard noticeLabel != nil else { return }
    let notice = PopoverNotice.notice(armed: recordingManager.state() != .unarmed,
                                      lidRisk: AppDelegate.sleepRiskMonitor.lidWouldStopWatching,
                                      gapStart: recordingManager.notWatchingFrom,
                                      gapEnd: recordingManager.notWatchingUntil,
                                      failure: recordingManager.recordingFailure,
                                      failureCount: recordingManager.recordingFailureCount,
                                      failedAt: recordingManager.recordingFailedAt,
                                      deletedCount: recordingManager.deletedCount,
                                      deletedAt: recordingManager.deletedAt,
                                      motionStopped: recordingManager.motionDetectionStopped,
                                      soundCanWatch: UserDefaults.standard.bool(forKey: "audioTriggerEnabled")
                                        && recordingManager.microphoneAvailable,
                                      freshStart: FreshStart.app.isPending,
                                      quitAt: recordingManager.quitUnexpectedlyAt,
                                      quitUntil: recordingManager.quitUnexpectedlyUntil,
                                      scheduleAtRisk: ScheduleRisk.current(loginState: loginState),
                                      update: UpdateNotice.app.pending)
    // Only the update line is a link; the rest keep the storyboard's warning colour.
    noticeLabel.textColor = noticeDefaultColor
    (noticeLabel as? ClickableLabel)?.isClickable = false
    switch notice {
    case .none:
      noticeLabel.stringValue = ""
    case let .updated(update):
      switch update {
      case .fromOlder:
        noticeLabel.stringValue = String(localized: "OnCue was updated from an older version. See what changed", comment: "Popover notice, a link to the changelog")
      case let .to(version):
        noticeLabel.stringValue = String(localized: "OnCue was updated to \(version). See what changed", comment: "Popover notice, a link to the changelog; the argument is a version")
      }
      noticeLabel.textColor = .linkColor
      (noticeLabel as? ClickableLabel)?.isClickable = true
    case .lidWouldStopWatching:
      noticeLabel.stringValue = String(localized: "Closing the lid will stop OnCue until it's opened again", comment: "Popover notice")
    case .scheduleCannotSurviveRestart:
      noticeLabel.stringValue = String(localized: "OnCue won't be open after a restart, so it can't arm itself. Turn on Open OnCue at Login in settings if you want that.", comment: "Popover notice; the schedule or arm-at-login is on and Open at Login is off")
    case let .motionDetectionStopped(soundStillWatching):
      noticeLabel.stringValue = soundStillWatching
        ? String(localized: "OnCue isn't watching for motion right now. Sound still is.", comment: "Popover notice")
        : String(localized: "OnCue isn't watching for motion right now.", comment: "Popover notice")
    case let .wasNotWatching(from, to):
      noticeLabel.stringValue = String(localized: "OnCue wasn't watching from \(PopoverViewController.time(from)) to \(PopoverViewController.time(to))", comment: "Popover notice; the arguments are times")
    case let .quitUnexpectedly(at, until):
      noticeLabel.stringValue = String(localized: "OnCue quit unexpectedly at \(PopoverViewController.moment(at)) and wasn't watching until \(PopoverViewController.moment(until))", comment: "Popover notice; the arguments are a time or a date and time")
    case let .recordingFailed(failure, count, _):
      noticeLabel.stringValue = failure.notice(count: count)
    case let .recordingsDeleted(count, _):
      noticeLabel.stringValue = String(localized: "The \(count) oldest recordings were deleted to stay under your limit", comment: "Popover notice; has a singular form in the catalog")
    case .freshStart:
      noticeLabel.stringValue = String(localized: "OnCue is starting with default settings.\nCheck the recordings folder and arm at login in Settings.", comment: "Popover notice, two lines")
    }
    layOutMotionColumn()
  }

  /// Says what went wrong in terms someone can act on, and how many recordings it has cost. One
  /// failure is bad luck; a run of them is a setup that needs fixing (spec 0027).
  private static func time(_ date: Date) -> String {
    DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
  }

  /// A time alone when it's today; the date too when it isn't, since a crash can be days old.
  static func moment(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
    if calendar.isDate(date, inSameDayAs: now) {
      return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }
    return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
  }

  private static func postQuitUnexpectedlyNotification(at: Date, until: Date) {
    let content = UNMutableNotificationContent()
    content.title = String(localized: "OnCue quit unexpectedly", comment: "Notification title")
    content.body = String(localized: "OnCue quit unexpectedly at \(moment(at)) and wasn't watching until \(moment(until)), so nothing was recorded in between.", comment: "Notification body; the arguments are a time or a date and time")
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "quit-unexpectedly", content: content, trigger: nil))
  }

  private static func postNotWatchingNotification(from start: Date, to end: Date) {
    let content = UNMutableNotificationContent()
    content.title = String(localized: "OnCue wasn't watching", comment: "Notification title")
    content.body = String(localized: "OnCue wasn't watching from \(time(start)) to \(time(end)), so nothing was recorded.", comment: "Notification body; the arguments are times")
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "sleep-gap", content: content, trigger: nil))
  }

  /// Keeps Arm in step with the triggers and devices. Disarming when nothing can trigger is
  /// RecordingManager's job; the state change comes back here through the observer.
  private func updateArmButton() {
    guard armedButton != nil else { return }
    armedButton.isEnabled = recordingManager.canArm()
  }

  @IBAction func arm(sender: NSButton) {
    switch AppDelegate.recordingManager.state() {
    case .unarmed:
      // The first arm asks for notification permission, so a sleep gap can be reported later.
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
      AppDelegate.recordingManager.startArming(countdown: 5)
    case .arming:
      fallthrough
    case .recording:
      fallthrough
    case .armed:
      AppDelegate.recordingManager.disarm()
    }
  }

  /// Points a meter's colours at the threshold it's being compared against (spec 0025), so green,
  /// yellow and red mean "wouldn't trigger", "nearly" and "would".
  private func colour(_ meter: NSLevelIndicator?, forThreshold threshold: Double) {
    guard let meter = meter else { return }
    let edges = MeterBands.edges(threshold: threshold)
    meter.warningValue = edges.warning
    meter.criticalValue = edges.critical
  }

  /// Re-colours all three meters from the thresholds in force now.
  private func colourMeters() {
    let captureManager = AppDelegate.captureManager
    colour(soundLevelIndicator, forThreshold: UserDefaults.standard.double(forKey: "audioTriggerThreshold"))
    colour(motionLevelIndicator,
           forThreshold: MotionDetector.threshold(cameraID: captureManager.currentVideoCaptureDevice?.uniqueID))
    colour(secondMotionLevelIndicator,
           forThreshold: MotionDetector.threshold(cameraID: captureManager.currentSecondVideoCaptureDevice?.uniqueID))
  }

  @IBAction func thresholdSliderValueChanged(_ sender: NSSlider) {
    MotionDetector.setThreshold(sender.doubleValue, cameraID: AppDelegate.captureManager.currentVideoCaptureDevice?.uniqueID)
    colour(motionLevelIndicator, forThreshold: sender.doubleValue)
  }

  @IBAction func motionTriggerToggled(_ sender: NSButton) {
    UserDefaults.standard.set(sender.state == .on, forKey: "motionTriggerEnabled")
    updateArmButton()
  }

  @IBAction func audioTriggerToggled(_ sender: NSButton) {
    UserDefaults.standard.set(sender.state == .on, forKey: "audioTriggerEnabled")
    updateArmButton()
  }

  @IBAction func audioThresholdSliderValueChanged(_ sender: NSSlider) {
    UserDefaults.standard.set(sender.doubleValue, forKey: "audioTriggerThreshold")
    colour(soundLevelIndicator, forThreshold: sender.doubleValue)
  }
}

extension PopoverViewController {
  #if DEBUG
  /// Meter levels for a store picture (spec 0057), where no camera feeds them.
  func setMetersForScreenshot(motion: Double, sound: Double, second: Double? = nil) {
    motionLevelIndicator.doubleValue = motion
    soundLevelIndicator.doubleValue = sound
    secondMotionLevelIndicator.doubleValue = second ?? 0
    describeMetersForAccessibility()
    colourMeters()
  }

  /// Everything the popover would redraw on opening, synchronously, for a store picture.
  func refreshForScreenshot() {
    updateArmButton()
    updateNotice()
    updateTriggerCost()
  }
  #endif

  static func freshController() -> PopoverViewController {
    let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
    let identifier = NSStoryboard.SceneIdentifier("PopoverViewController")
    guard let viewcontroller = storyboard.instantiateController(withIdentifier: identifier) as? PopoverViewController else {
      fatalError("Why can't I find PopoverViewController? - Check Main.storyboard")
    }
    let _ = viewcontroller.view
    viewcontroller.thresholdSlider.doubleValue = UserDefaults.standard.double(forKey: "motionTriggerThreshold")
    viewcontroller.motionTriggerCheckbox.state = UserDefaults.standard.bool(forKey: "motionTriggerEnabled") ? .on : .off
    viewcontroller.audioTriggerCheckbox.state = UserDefaults.standard.bool(forKey: "audioTriggerEnabled") ? .on : .off
    viewcontroller.audioThresholdSlider.doubleValue = UserDefaults.standard.double(forKey: "audioTriggerThreshold")
    viewcontroller.updateArmButton()
    viewcontroller.colourMeters()
    return viewcontroller
  }
}

extension PopoverViewController {
  @IBAction func toggleFloatMode(_ sender: NSButton) {
    floatPopover = sender.state == .on
  }

  @IBAction func togglePreviewWindow(_ sender: NSButton) {
    self.togglePreviewWindow()
  }

  // MARK: - Accessibility (spec 0049)

  /// Names for VoiceOver, Voice Control and Switch Control. Two checkboxes both titled Trigger,
  /// two sliders, three meters and two picture-only buttons had no name a screen reader could
  /// tell apart; the labels that matter visually are in the headers, which a reader never
  /// reaches from the control.
  private func labelControlsForAccessibility() {
    soundLevelIndicator.setAccessibilityLabel(String(localized: "Sound level", comment: "Accessibility label, popover meter"))
    audioTriggerCheckbox.setAccessibilityLabel(String(localized: "Sound trigger", comment: "Accessibility label, popover checkbox"))
    audioThresholdSlider.setAccessibilityLabel(String(localized: "Sound threshold", comment: "Accessibility label, popover slider"))
    motionLevelIndicator.setAccessibilityLabel(String(localized: "Motion level", comment: "Accessibility label, popover meter"))
    motionTriggerCheckbox.setAccessibilityLabel(String(localized: "Motion trigger", comment: "Accessibility label, popover checkbox"))
    thresholdSlider.setAccessibilityLabel(String(localized: "Motion threshold", comment: "Accessibility label, popover slider"))
    secondMotionLevelIndicator.setAccessibilityLabel(String(localized: "Second camera level", comment: "Accessibility label, popover meter"))
    secondThresholdSlider.setAccessibilityLabel(String(localized: "Second camera threshold", comment: "Accessibility label, popover slider"))
    floatButton.setAccessibilityLabel(String(localized: "Keep the popover open", comment: "Accessibility label, popover pin button"))
    menuButton.setAccessibilityLabel(String(localized: "Menu", comment: "Accessibility label, popover gear button"))
    describeMetersForAccessibility()
  }

  /// The meters show a level a reader can't see; this says it as a number whenever it moves.
  private func describeMeterForAccessibility(_ meter: NSLevelIndicator) {
    let percent = Int(meter.doubleValue.rounded())
    meter.setAccessibilityValueDescription(String(localized: "\(percent) percent", comment: "Accessibility value of a popover meter; the argument is 0 to 100"))
  }

  /// Reachable by selector so the accessibility test, which runs inside the app, can ask.
  @objc func describeMetersForAccessibility() {
    for meter in [motionLevelIndicator, soundLevelIndicator, secondMotionLevelIndicator] {
      if let meter = meter { describeMeterForAccessibility(meter) }
    }
  }

  @IBAction func showPopoverMenu(_ sender: NSButton) {
    let p = NSPoint(x: 0, y: sender.frame.height)
    popoverMenu.popUp(positioning: nil, at: p, in: sender)
  }

  func togglePreviewWindow() {
    guard let window = previewWindowController.window else { return }

    if window.isVisible {
      window.orderOut(window)
    } else {
      // Closing the window with its own button doesn't come back through here, so capture hears
      // about it from the window itself (spec 0023).
      if previewCloseObserver == nil {
        previewCloseObserver = NotificationCenter.default.addObserver(
          forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            AppDelegate.captureManager.previewOpen = false
        }
      }
      previewWindowController.showWindow(self)
    }
    AppDelegate.captureManager.previewOpen = window.isVisible
  }
}

extension PopoverViewController {
  func popoverShouldClose(_ popover: NSPopover) -> Bool {
    return !floatPopover
  }

  /// Capture runs while the popover is open, so the meters have something to show (spec 0023).
  /// These fire on what actually happened, so a close the popover refuses doesn't count.
  func popoverDidShow(_ notification: Notification) {
    AppDelegate.captureManager.popoverOpen = true
    updateTriggerCost()
    // Open at Login can change in System Settings, which nothing here observes (spec 0051).
    refreshLoginState()
  }

  /// Asks macOS for the login item off the main thread each time the popover opens; the notice
  /// waits for the answer rather than showing a warning that might be wrong (spec 0051).
  private func refreshLoginState() {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let state = LoginItem.app.state
      DispatchQueue.main.async {
        self?.loginState = state
        self?.updateNotice()
      }
    }
  }

  func popoverDidClose(_ notification: Notification) {
    recordingManager.clearTimeLapseFailure()
    AppDelegate.captureManager.popoverOpen = false
  }
}

extension PopoverViewController: CaptureManagerActivityDelegate {
  /// A meter showing a level nothing is measuring is the worst thing the popover could do here: at
  /// zero it looks exactly like a working camera watching a still room, which is the picture of
  /// everything being fine. Disabled is the idiom for "not reflecting anything right now", and the
  /// threshold slider stays live because the setting still matters for when detection returns.
  func motionDetectionChanged(stopped: [Bool]) {
    DispatchQueue.main.async {
      guard self.motionLevelIndicator != nil else { return }
      let meters = [self.motionLevelIndicator, self.secondMotionLevelIndicator]
      for (camera, meter) in meters.enumerated() {
        let isStopped = camera < stopped.count && stopped[camera]
        meter?.isEnabled = !isStopped
      }
    }
  }

  func motionActivityReported(activity: Double, camera: Int) {
    if (self.motionLevelIndicator != nil) {
      DispatchQueue.main.async {
        let meter: NSLevelIndicator = camera == 0 ? self.motionLevelIndicator : self.secondMotionLevelIndicator
        meter.doubleValue = (meter.doubleValue + activity) / 2
        self.describeMeterForAccessibility(meter)
        // Frames only arrive while a camera is open, which is exactly when Edge Light can be on.
        self.updateEdgeLightWarning()
      }
    }
  }

  func soundActivityReported(level: Double) {
    if (self.soundLevelIndicator != nil) {
      DispatchQueue.main.async {
        self.soundLevelIndicator.doubleValue = (self.soundLevelIndicator.doubleValue + level) / 2
        self.describeMeterForAccessibility(self.soundLevelIndicator)
      }
    }
  }

  /// Names the device under each header. A column with no device has nothing to meter or trigger
  /// on, so it's disabled; the saved settings are left alone, so they apply again once it's back.
  func devicesChanged(cameraName: String?, secondCameraName: String?, microphoneName: String?) {
    updateArmButton()
    guard self.soundLevelIndicator != nil else { return }
    motionDeviceLabel.stringValue = cameraName ?? ""
    soundDeviceLabel.stringValue = microphoneName ?? ""
    thresholdSlider.doubleValue = MotionDetector.threshold(cameraID: AppDelegate.captureManager.currentVideoCaptureDevice?.uniqueID)
    showSecondCamera(named: secondCameraName)
    // Choosing no device switches its trigger off, and these are read once at creation otherwise
    // (spec 0028).
    motionTriggerCheckbox.state = UserDefaults.standard.bool(forKey: "motionTriggerEnabled") ? .on : .off
    audioTriggerCheckbox.state = UserDefaults.standard.bool(forKey: "audioTriggerEnabled") ? .on : .off
    // A different camera has its own threshold, so the colours move with it.
    colourMeters()
    // Losing the last camera takes the Edge Light line with it.
    updateEdgeLightWarning()
    let camera = cameraName != nil
    let microphone = microphoneName != nil
    for control in [motionLevelIndicator, motionTriggerCheckbox, thresholdSlider] as [NSControl] {
      control.isEnabled = camera
    }
    for control in [soundLevelIndicator, audioTriggerCheckbox, audioThresholdSlider] as [NSControl] {
      control.isEnabled = microphone
    }
    if !camera {
      motionLevelIndicator.doubleValue = 0
    }
    if !microphone {
      soundLevelIndicator.doubleValue = 0
    }
  }
}

/// A label that shows the pointing hand while it's acting as a button (spec 0054), and the
/// arrow otherwise. A plain text field offers the I-beam, which says "select me", not "click me".
final class ClickableLabel: NSTextField {
  var isClickable = false {
    didSet { window?.invalidateCursorRects(for: self) }
  }

  override func resetCursorRects() {
    super.resetCursorRects()
    if isClickable {
      addCursorRect(bounds, cursor: .pointingHand)
    }
  }
}
