//
//  RecordingManager.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 2/2/20.
//  Copyright © 2020 Jake Van Alstyne
//

import Cocoa
import AVFoundation

/// What RecordingManager needs from a camera's recorder, so tests can stand in a fake.
protocol MovieRecorder: AnyObject {
  /// When the footage a recording started now would begin, pre-roll included (spec 0013).
  var footageStart: Date { get }
  /// `onFinish` is called once the file is complete, from any queue, with the error if it ended badly.
  func startRecording(to url: URL, onFinish: @escaping (URL, Error?) -> Void)
  /// Finish the open file at the next keyframe and carry on in `url`, so nothing falls between the
  /// two (spec 0031).
  func roll(to url: URL, onFinish: @escaping (URL, Error?) -> Void)
  func stopRecording()
}

/// One camera's share of a recording: where it records, and the devices its file is named after.
struct RecordingTarget {
  let recorder: MovieRecorder
  let cameraName: String?
  let microphoneName: String?
}

class RecordingManager: NSObject {
  private let fileOutputManager = FileOutputManager()
  /// The recorders writing the current recording, one per camera.
  private var recorders: [MovieRecorder] = []
  /// The paths being written, so a finish callback for an earlier file can be told apart from these.
  private var currentFilePaths = Set<String>()
  /// What the current recording is recording, kept so a roll can name its next files the same way.
  private var currentTargets: [RecordingTarget] = []
  /// Set when a recording is being ended because the disk is nearly full, so the reason survives
  /// the clean finish that follows (spec 0031).
  private var stoppingForSpace = false

  private let defaults: UserDefaults
  /// Device presence, reported by CaptureManager on the main queue. Unknown until the first
  /// report, so treated as absent: nothing can arm before capture is configured.
  private(set) var cameraAvailable = false
  private(set) var microphoneAvailable = false
  private var defaultsObserver: NSObjectProtocol?

  /// Whether the schedule is what armed OnCue (spec 0038). A window's end only disarms when this
  /// is set; any disarm clears it. Observed by the popover for its "until" line.
  @objc dynamic private(set) var armedBySchedule = false
  /// Whether a Focus Filter is what armed OnCue (spec 0050). A Focus ending disarms only when
  /// this is set; any disarm clears it.
  @objc dynamic private(set) var armedByFocus = false
  /// Whether the last look found us inside a window. nil until the first look, and reset to nil
  /// when the schedule changes, so a window already under way counts as entered.
  private var insideScheduleWindow: Bool?
  private var scheduleTimer: Timer?
  /// The schedule as last read from defaults, so a change to it can be told from any other
  /// defaults change.
  private var schedule = Schedule()
  private var scheduleEnabled = false
  /// Bumped when the schedule changes and on each minute's look while unarmed, so the state
  /// line's "until <next start>" follows the clock and the rows (spec 0044).
  @objc dynamic private(set) var scheduleGeneration = 0
  /// The clock the schedule is checked against. Tests set it; the app never does.
  var clock: () -> Date = { Date() }

  /// The last recording that failed to write, kept until disarm so it's still there when whoever
  /// was away comes back (spec 0027). `failedAt` is set last, so observing it sees a whole failure.
  @objc dynamic private(set) var recordingFailedAt: Date?
  private(set) var recordingFailure: RecordingFailure?
  /// Consecutive failures, so ten in a row doesn't read like one piece of bad luck. Reset by a
  /// recording that works, and by disarming.
  private(set) var recordingFailureCount = 0
  /// Whether the menu bar icon should say something is wrong.
  var hasRecordingFailure: Bool { recordingFailure != nil }

  /// Recordings the rolling window deleted, kept until disarm so footage never goes without a
  /// word (spec 0029).
  @objc dynamic private(set) var deletedAt: Date?
  private(set) var deletedCount = 0

  /// The last stretch where OnCue wasn't watching while armed, kept until disarm so whoever was
  /// away can see there's a hole. The Mac sleeping is one cause; motion detection stopping is the
  /// other (spec 0030). `notWatchingUntil` is set last, so observing it sees a complete gap.
  @objc dynamic private(set) var notWatchingFrom: Date?
  @objc dynamic private(set) var notWatchingUntil: Date?
  /// The previous run ended while armed without a disarm or a normal quit (spec 0045): when it
  /// was last known to be watching, and when this run began. `quitUnexpectedlyUntil` is set
  /// last, so observing it sees a complete pair. Cleared by the next disarm, like the gap.
  @objc dynamic private(set) var quitUnexpectedlyAt: Date?
  @objc dynamic private(set) var quitUnexpectedlyUntil: Date?
  private var recoveredAtLaunch = false
  private var sleptAt: Date?

  /// Tests pass their own defaults, so they never touch the app's real settings.
  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    super.init()
    schedule = Schedule.load(from: defaults)
    scheduleEnabled = Schedule.isEnabled(in: defaults)
    updateKeepAwake()
    // A trigger toggle changing can leave nothing able to fire.
    defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                              object: defaults, queue: .main) { [weak self] _ in
      self?.disarmIfNothingCanTrigger()
      self?.scheduleMayHaveChanged()
    }
    // A minute is the finest a schedule is set in, so a minute is how often it's looked at, and
    // the looks land on the minute: a timer started at launch would fire at whatever second the
    // app happened to start, and a window's end would be noticed up to 59 seconds late.
    let nextMinute = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 / 60).rounded(.up) * 60)
    scheduleTimer = Timer(fire: nextMinute, interval: 60, repeats: true) { [weak self] _ in
      self?.checkSchedule()
    }
    RunLoop.main.add(scheduleTimer!, forMode: .common)
    let workspace = NSWorkspace.shared.notificationCenter
    workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
      self?.systemWillSleep(at: Date())
    }
    workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
      self?.systemDidWake(at: Date())
    }
  }

  func systemWillSleep(at date: Date) {
    guard state() != .unarmed else { return }
    sleptAt = date
  }

  func systemDidWake(at date: Date) {
    checkSchedule(now: date)
    guard let start = sleptAt else { return }
    sleptAt = nil
    noteNotWatching(from: start, to: date)
  }

  /// A stretch with no footage in it, whatever caused it. Only while armed: unarmed, OnCue wasn't
  /// meant to be watching and nothing was missed.
  func noteNotWatching(from start: Date, to end: Date) {
    guard state() != .unarmed else { return }
    notWatchingFrom = start
    notWatchingUntil = end
  }

  /// Motion detection stopped measuring, or started again (spec 0030). Kept only while it's true:
  /// the outage it leaves behind is reported separately, as a gap.
  @objc dynamic private(set) var motionDetectionStopped = false

  func motionDetectionChanged(stopped: Bool) {
    guard stopped != motionDetectionStopped else { return }
    motionDetectionStopped = stopped
    // Arm is refused while nothing can fire, but an armed OnCue is left alone: disarming happens
    // after whoever armed it has walked away, and nobody is there to undo it (spec 0030).
  }

  deinit {
    if let observer = defaultsObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    scheduleTimer?.invalidate()
  }

  /// What the trigger has been producing over the last day (spec 0033), or nil when there isn't
  /// enough in the window to say anything true. Reads the folder, so it's for opening a popover
  /// rather than for anything on a timer.
  func triggerCost(now: Date = Date()) -> TriggerCost.Summary? {
    return TriggerCost.summary(recordings: fileOutputManager.ownRecordings(), now: now,
                               bitsPerSecond: TriggerCost.assumedBitsPerSecond,
                               preRoll: PreRoll.seconds(defaults: defaults),
                               timeout: min(max(defaults.integer(forKey: "timeoutValueInSeconds"), 0), 600))
  }

  /// Settings changed where recordings are saved.
  func recordingsFolderChanged() {
    fileOutputManager.setFolder(RecordingsFolder.current().folder)
  }

  /// Fifteen seconds, longer than the Arm button's five, so there's time to notice and cancel after
  /// a restart (spec 0018).
  static let launchCountdown = 15
  private var armedAtLaunch = false
  /// Called when OnCue arms itself, so it can say so.
  var onArmedAtLaunch: (() -> Void)?
  /// Called once every file of a recording has finished being written. Quitting waits for this:
  /// a file whose writing is cut short has no index and won't open (spec 0013's recorder).
  var onRecordingsFinished: (() -> Void)?

  func deviceAvailabilityChanged(camera: Bool, microphone: Bool) {
    cameraAvailable = camera
    microphoneAvailable = microphone
    disarmIfNothingCanTrigger()
    recoverFromUnexpectedQuit()
    armAtLaunchIfWanted()
    checkSchedule()
  }

  /// The launch moment's first look (spec 0045): a record the previous run left means it ended
  /// while armed. Say so, and arm again unless the schedule had armed it and no window is open.
  /// Once per launch, before arm-at-login, which then sees `armedAtLaunch` set and stands down.
  func recoverFromUnexpectedQuit() {
    guard !recoveredAtLaunch else { return }
    recoveredAtLaunch = true
    let now = clock()
    guard let recovery = ArmedRecord.recovery(from: ArmedRecord.read(from: defaults),
                                              insideWindowNow: scheduleEnabled && schedule.contains(now)) else {
      ArmedStretch.clearArmedSince(in: defaults)
      return
    }
    ArmedRecord.clear(in: defaults)
    // The stretch the crash cut short ends at the last minute OnCue was seen (spec 0054).
    closeStretch(at: recovery.gapStart, suppressed: false)
    if recovery.rearm {
      armedAtLaunch = true
      armedBySchedule = recovery.bySchedule
      startArming(countdown: RecordingManager.launchCountdown)
      onArmedAtLaunch?()
    }
    quitUnexpectedlyAt = recovery.gapStart
    quitUnexpectedlyUntil = now
  }

  // MARK: - A Focus Filter (spec 0050)

  /// A Focus with the filter became active (`wantsArmed` true) or the arming Focus ended
  /// (false). Arming here is arming nobody watched: the launch countdown and the notification.
  func focusChanged(wantsArmed: Bool) {
    let action = FocusArming.action(wantsArmed: wantsArmed, state: state(), armedByFocus: armedByFocus,
                                    canFire: RecordingManager.canAnyTriggerFire(motionEnabled: motionEnabled, cameraAvailable: cameraAvailable,
                                                                                audioEnabled: audioEnabled, audioAvailable: microphoneAvailable))
    switch action {
    case .arm:
      armedByFocus = true
      startArming(countdown: RecordingManager.launchCountdown)
      onArmedAtLaunch?()
    case .disarm:
      disarm()
    case .none:
      break
    }
  }

  // MARK: - Record a test (spec 0046)

  /// Fires the recording path a trigger fires: every running camera, the normal timeout after.
  /// The capture manager registers it.
  var onTestRecordingWanted: (() -> Void)?
  /// A test's first file finished without error; the popover menu reveals it in Finder.
  var onTestRecordingFinished: ((URL) -> Void)?
  /// From the menu item to the cleanup, so the item disables and the cleanup knows its work.
  @objc dynamic private(set) var isRecordingTest = false
  private var testArmedItself = false
  private var pendingTestFiles = 0
  private var testRevealed = false

  /// Whether Record a Test is offered: unarmed with something that can fire, or armed. Not while
  /// arming or recording.
  static func canRecordTest(state: ArmState, canArm: Bool) -> Bool {
    switch state {
    case .unarmed: return canArm
    case .armed: return true
    case .arming, .recording: return false
    }
  }

  /// From unarmed, the countdown fills the pre-roll ring, which is empty while capture isn't
  /// running (0023): as long as the setting needs, and never less than Arm's five seconds.
  static func testCountdown(preRollSeconds: Double) -> Int {
    return max(5, Int(preRollSeconds.rounded(.up)))
  }

  func recordTest() {
    guard RecordingManager.canRecordTest(state: state(), canArm: canArm()), !isRecordingTest else { return }
    isRecordingTest = true
    testRevealed = false
    testArmedItself = state() == .unarmed
    if testArmedItself {
      startArming(countdown: RecordingManager.testCountdown(preRollSeconds: PreRoll.seconds(defaults: defaults)))
    }
    // A countdown of zero, or a Debug build (0002), is armed already; otherwise `countdown()` fires it.
    if state() == .armed {
      fireTest()
    }
  }

  /// Asks capture for the trigger's path. The answer comes back through `startRecording(to:)`,
  /// which either begins the recording or refuses it, because capture may still be starting:
  /// from unarmed with the popover closed, the cameras start on arming and take a moment. If
  /// nothing answers at all (a camera that never comes up), the deadline ends the test.
  private func fireTest() {
    let deadline = DispatchWorkItem { [weak self] in self?.finishTest() }
    testDeadline = deadline
    DispatchQueue.main.asyncAfter(deadline: .now() + RecordingManager.testStartDeadline, execute: deadline)
    onTestRecordingWanted?()
  }

  /// How long a test waits for capture to come up before giving up.
  static let testStartDeadline: TimeInterval = 15
  private var testDeadline: DispatchWorkItem?

  /// Capture answered: the recording began (`recorders` are running) or was refused.
  private func testRecordingAnswered(started: Bool) {
    guard isRecordingTest else { return }
    testDeadline?.cancel()
    testDeadline = nil
    if started {
      pendingTestFiles = recorders.count
    } else {
      // No room, or nothing to record on. Whatever refused it has said so; the test is over.
      finishTest()
    }
  }

  private func testFileFinished(url: URL, error: Error?) {
    if error == nil && !testRevealed {
      testRevealed = true
      onTestRecordingFinished?(url)
    }
    pendingTestFiles -= 1
    if pendingTestFiles <= 0 {
      finishTest()
    }
  }

  /// Back to how it was, keeping what the test found: a disarm here must not wipe the failure
  /// the person pressed the button to learn about.
  private func finishTest() {
    guard isRecordingTest else { return }
    isRecordingTest = false
    pendingTestFiles = 0
    testDeadline?.cancel()
    testDeadline = nil
    if testArmedItself {
      testArmedItself = false
      stretchSuppressed = true
      disarm(keepingNotices: true)
      stretchSuppressed = false
    }
  }

  /// A normal quit while armed leaves no record behind, so the next launch has nothing to recover.
  func noteNormalQuit() {
    ArmedRecord.clear(in: defaults)
    if state() != .unarmed {
      closeStretch(at: clock(), suppressed: false)
    }
  }

  private func refreshArmedRecord(now: Date) {
    guard state() != .unarmed else { return }
    ArmedRecord(lastSeen: now, bySchedule: armedBySchedule).write(to: defaults)
  }

  // MARK: - Arming on a schedule (spec 0038)

  /// Re-reads the schedule after a defaults change. Only a change to the schedule itself resets
  /// the last look, so that a window already under way counts as entered under the new rows; any
  /// other defaults write leaves the schedule's memory alone.
  private func scheduleMayHaveChanged() {
    #if DEBUG
    // A picture's state is set by hand and must not be undone by the next defaults write.
    if frozenForScreenshot { return }
    #endif
    let now = Schedule.load(from: defaults), enabled = Schedule.isEnabled(in: defaults)
    guard now != schedule || enabled != scheduleEnabled else { return }
    schedule = now
    scheduleEnabled = enabled
    insideScheduleWindow = nil
    scheduleGeneration += 1
    updateKeepAwake()
    checkSchedule()
  }

  /// One look at the clock. Acts only on the change since the last look (see `Schedule.action`),
  /// which is what keeps a manual disarm from being overridden a minute later.
  func checkSchedule() {
    checkSchedule(now: clock())
  }

  func checkSchedule(now: Date) {
    let inside = scheduleEnabled && schedule.contains(now)
    let action = Schedule.action(enabled: scheduleEnabled, insideNow: inside, insideBefore: insideScheduleWindow,
                                 state: state(), armedBySchedule: armedBySchedule,
                                 canFire: RecordingManager.canAnyTriggerFire(motionEnabled: motionEnabled, cameraAvailable: cameraAvailable,
                                                                             audioEnabled: audioEnabled, audioAvailable: microphoneAvailable))
    insideScheduleWindow = inside
    switch action {
    case .arm:
      armedBySchedule = true
      startArming(countdown: RecordingManager.launchCountdown)
      onArmedAtLaunch?()
    case .disarm:
      disarm()
    case .none:
      break
    }
    if scheduleEnabled && state() == .unarmed {
      scheduleGeneration += 1
    }
    refreshArmedRecord(now: now)
  }

  /// The next window's start, for the popover while unarmed. nil unless the schedule is on and
  /// something is coming.
  func nextScheduledStart() -> Date? {
    guard scheduleEnabled else { return nil }
    return schedule.nextStart(after: clock())
  }

  /// When the window OnCue is armed under ends, for the popover. nil unless the schedule armed it.
  func scheduledWindowEnd() -> Date? {
    guard armedBySchedule else { return nil }
    return schedule.end(of: clock())
  }

  /// Arms itself once after launch, when Settings asks for it. Waits for capture to report its
  /// devices, so it doesn't arm before knowing whether anything can fire.
  func armAtLaunchIfWanted() {
    guard !armedAtLaunch,
      RecordingManager.shouldArmAtLaunch(enabled: defaults.bool(forKey: "armAtLogin"), state: state(),
                                         motionEnabled: motionEnabled, cameraAvailable: cameraAvailable,
                                         audioEnabled: audioEnabled, audioAvailable: microphoneAvailable) else {
      return
    }
    armedAtLaunch = true
    startArming(countdown: RecordingManager.launchCountdown)
    onArmedAtLaunch?()
  }

  private var motionEnabled: Bool { defaults.bool(forKey: "motionTriggerEnabled") }
  private var audioEnabled: Bool { defaults.bool(forKey: "audioTriggerEnabled") }

  /// Whether Arm should be offered now, from the current toggles and devices.
  func canArm() -> Bool {
    return RecordingManager.armingAllowed(state: state(), motionEnabled: motionEnabled, cameraAvailable: cameraAvailable,
                                          audioEnabled: audioEnabled, audioAvailable: microphoneAvailable,
                                          motionWorking: !motionDetectionStopped)
  }

  private func disarmIfNothingCanTrigger() {
    if RecordingManager.shouldAutoDisarm(state: state(), motionEnabled: motionEnabled, cameraAvailable: cameraAvailable,
                                         audioEnabled: audioEnabled, audioAvailable: microphoneAvailable) {
      disarm()
    }
  }

  enum ArmState : NSNumber {
    case unarmed = 0
    case arming = 1
    case armed = 2
    case recording = 3
  }

  @objc dynamic private(set) var armedStateRaw: NSNumber?
  private var armedState: ArmState? = .unarmed {
    didSet{
      armedStateRaw = armedState?.rawValue
      updateKeepAwake()
      updateDuringRecordingChecks()
      noteStretch(from: oldValue, to: armedState)
    }
  }

  #if DEBUG
  // MARK: - Drawn for the store (spec 0057)

  /// Set once a picture's state has been put in by hand. Until then any defaults write made
  /// `scheduleMayHaveChanged` re-read the schedule the overrides enable and arm the popover on
  /// it, so the "unarmed" picture shipped saying "Armed on schedule" (found 2026-11-09, 0061).
  private var frozenForScreenshot = false

  /// Puts the manager in a state for a picture, with no countdown timer, no record and no
  /// stretch written: the pictures are made before the run loop turns and the process quits.
  func setStateForScreenshot(_ state: ArmState, countdown: Int, bySchedule: Bool) {
    frozenForScreenshot = true
    // Devices present, or the first defaults write (arming clears the fresh-start flag) would
    // auto-disarm it; the schedule only for the picture that says "on schedule".
    cameraAvailable = true
    microphoneAvailable = true
    scheduleEnabled = bySchedule
    stretchSuppressed = true
    armingCountdown = countdown
    armedBySchedule = bySchedule
    armedState = state
    stretchSuppressed = false
  }

  /// The folder the stretch line reads, so a picture can show recordings that aren't the user's.
  func useRecordingsFolderForScreenshot(_ folder: URL) {
    fileOutputManager.setFolder(folder)
  }
  #endif

  // MARK: - What happened while armed (spec 0054)

  /// Bumped when a stretch is remembered, so the popover re-reads the line.
  @objc dynamic private(set) var stretchGeneration = 0
  /// A test's own cleanup disarm isn't the end of an outing (spec 0046), so it writes nothing.
  private var stretchSuppressed = false

  /// Every route out of armed passes through the state, so this is the one place a stretch
  /// closes. It opens beside 0045's record, before the state changes: a defaults write while
  /// armed is what the auto-disarm observer reacts to.
  private func noteStretch(from old: ArmState?, to new: ArmState?) {
    if old != .unarmed, new == .unarmed {
      closeStretch(at: clock(), suppressed: stretchSuppressed)
    }
  }

  private func closeStretch(at end: Date, suppressed: Bool) {
    guard let since = ArmedStretch.armedSince(in: defaults) else { return }
    ArmedStretch.clearArmedSince(in: defaults)
    guard !suppressed else { return }
    remember(ArmedStretch(from: since, to: end))
  }

  /// Keeps the stretch if it's worth a line, replacing the one before it.
  private func remember(_ stretch: ArmedStretch) {
    let events = ArmedStretch.events(in: fileOutputManager.ownRecordings(), stretch: stretch,
                                     preRoll: PreRoll.seconds(defaults: defaults))
    guard ArmedStretch.isWorthKeeping(stretch, eventCount: events.count) else { return }
    stretch.write(to: defaults)
    stretchGeneration += 1
  }

  /// The remembered stretch and what it held, read from the folder now.
  struct WhatHappened: Equatable {
    let stretch: ArmedStretch
    let events: [ArmedStretch.Event]
    var text: String { ArmedStretch.summary(stretch, events: events) }
    var files: [URL] { ArmedStretch.files(of: events) }
    /// Whether there's anything for Finder to select: the menu item and the line's click.
    var canShow: Bool { !files.isEmpty }
  }

  // MARK: - A time-lapse of the stretch (spec 0055)

  /// True while one is being written; the menu item is off meanwhile.
  @objc dynamic private(set) var isMakingTimeLapse = false
  /// Set when nothing in the stretch could be read; the popover's line says so until it closes.
  @objc dynamic private(set) var timeLapseFailed = false

  /// Where recordings go now, for the time-lapse to land beside them.
  var recordingsFolder: URL { fileOutputManager.oncuePath }

  func timeLapseStarted() {
    isMakingTimeLapse = true
    timeLapseFailed = false
  }

  func timeLapseFinished(readable: Bool) {
    isMakingTimeLapse = false
    timeLapseFailed = !readable
  }

  func clearTimeLapseFailure() {
    timeLapseFailed = false
  }

  /// Nil until a stretch worth a line has finished. Reads the folder, so it's for a popover
  /// opening or a menu validating, not a timer.
  func whatHappened() -> WhatHappened? {
    guard let stretch = ArmedStretch.read(from: defaults) else { return nil }
    let events = ArmedStretch.events(in: fileOutputManager.ownRecordings(), stretch: stretch,
                                     preRoll: PreRoll.seconds(defaults: defaults))
    return WhatHappened(stretch: stretch, events: events)
  }

  // Capture stops when the Mac sleeps, so hold off idle sleep from arming until disarmed, and
  // the whole time a schedule with a window is on (spec 0044): a Mac asleep between windows
  // can't notice the next one start, and nothing in a sandboxed app can wake it.
  // This doesn't prevent sleep from closing the lid.
  private var keepAwakeActivity: NSObjectProtocol?
  private var keepAwakeReason: KeepAwakeReason?

  /// Why the Mac is being kept awake, as Activity Monitor shows it. Armed wins over the schedule
  /// while both apply.
  enum KeepAwakeReason: Equatable {
    case armed, schedule
  }

  var isKeepingAwake: Bool {
    keepAwakeActivity != nil
  }

  /// What the assertion is for right now, or nil when the Mac may sleep.
  var keepingAwakeFor: KeepAwakeReason? {
    keepAwakeReason
  }

  static func keepAwakeReason(state: ArmState?, scheduleEnabled: Bool, nextStart: Date?) -> KeepAwakeReason? {
    if state != .unarmed && state != nil { return .armed }
    if scheduleEnabled && nextStart != nil { return .schedule }
    return nil
  }

  private func updateKeepAwake() {
    let wanted = RecordingManager.keepAwakeReason(state: armedState, scheduleEnabled: scheduleEnabled,
                                                  nextStart: schedule.nextStart(after: clock()))
    guard wanted != keepAwakeReason else { return }
    if let activity = keepAwakeActivity {
      ProcessInfo.processInfo.endActivity(activity)
      keepAwakeActivity = nil
    }
    keepAwakeReason = wanted
    guard let reason = wanted else { return }
    let text: String
    switch reason {
    case .armed:
      text = String(localized: "OnCue is armed", comment: "Why the Mac is kept awake, as Activity Monitor shows it")
    case .schedule:
      text = String(localized: "OnCue is waiting for its schedule", comment: "Why the Mac is kept awake between schedule windows, as Activity Monitor shows it")
    }
    // .userInitiated includes .idleSystemSleepDisabled and also keeps App Nap from throttling capture.
    keepAwakeActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: text)
  }

  @objc private class func keyPathsForValuesAffectingArmedButtonText() -> Set<String> {
    return [#keyPath(armedStateRaw)]
  }
  /// A window's end as the popover names it: the time alone when it's today, "tomorrow" when a
  /// window crosses midnight, and the weekday beyond that, so "until 17:00" never means a day
  /// other than the one it reads as.
  static func describe(end: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
    let time = DateFormatter.localizedString(from: end, dateStyle: .none, timeStyle: .short)
    if calendar.isDate(end, inSameDayAs: now) {
      return time
    }
    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(end, inSameDayAs: tomorrow) {
      return String(localized: "\(time) tomorrow", comment: "When a schedule window ends; the argument is a time")
    }
    let weekday = calendar.weekdaySymbols[calendar.component(.weekday, from: end) - 1]
    return String(localized: "\(time) on \(weekday)", comment: "When a schedule window ends; the arguments are a time and a weekday")
  }

  @objc private class func keyPathsForValuesAffectingArmedStateDescription() -> Set<String> {
    return [#keyPath(armedStateRaw), #keyPath(armedBySchedule), #keyPath(armedByFocus), #keyPath(scheduleGeneration)]
  }
  @objc private class func keyPathsForValuesAffectingArmedStateColor() -> Set<String> {
    return [#keyPath(armedStateRaw)]
  }

  @objc dynamic var armedStateDescription: String {
    get {
      switch armedState {
      case .unarmed:
        if let next = nextScheduledStart() {
          return String(localized: "Unarmed until \(RecordingManager.describe(end: next, now: clock()))", comment: "Armed state between schedule windows; the argument is when the next window starts")
        }
        return String(localized: "Unarmed", comment: "Armed state")
      case .arming:
        return String(localized: "Arming… \(armingCountdown)", comment: "Armed state; the argument is the countdown in seconds")
      case .armed:
        if let end = scheduledWindowEnd() {
          return String(localized: "Armed on schedule until \(RecordingManager.describe(end: end))", comment: "Armed state; the argument is when the window ends")
        }
        if armedByFocus {
          return String(localized: "Armed by Focus", comment: "Armed state while a Focus Filter armed it")
        }
        return String(localized: "Armed", comment: "Armed state")
      case .recording:
        return String(localized: "Recording", comment: "Armed state")
      case .none:
        return String(localized: "Unarmed", comment: "Armed state")
      }
    }
  }
  @objc dynamic var armedStateColor: NSColor {
    get {
      switch armedState {
      case .arming:
        return .systemOrange
      case .armed:
        fallthrough
      case .recording:
        return .systemRed
      case .unarmed:
        fallthrough
      case .none:
        // The label colour, not white: white text vanishes on a light popover. The app follows
        // the system appearance and had only ever been looked at in dark mode (2026-09-23).
        return .labelColor
      }
    }
  }
  @objc dynamic var armedButtonText: String {
    switch armedState {
    case .arming:
      fallthrough
    case .recording:
      fallthrough
    case .armed:
      return String(localized: "Disarm", comment: "Popover button")
    case .unarmed:
      fallthrough
    case .none:
      return String(localized: "Arm", comment: "Popover button")
    }
  }

  private(set) var armingCountdown: Int = 0
  private var countdownTimer: Timer!

  /// A trigger counts only if it's on and its device is present: motion needs a camera, sound a mic.
  /// `motionWorking` is whether motion is actually being measured (spec 0030). A camera that is
  /// present but measuring nothing can't fire any more than a missing one can.
  class func canAnyTriggerFire(motionEnabled: Bool, cameraAvailable: Bool, audioEnabled: Bool,
                               audioAvailable: Bool, motionWorking: Bool = true) -> Bool {
    return (motionEnabled && cameraAvailable && motionWorking) || (audioEnabled && audioAvailable)
  }

  /// Arming only makes sense if something can start a recording. Disarming is always allowed.
  class func armingAllowed(state: ArmState, motionEnabled: Bool, cameraAvailable: Bool, audioEnabled: Bool,
                           audioAvailable: Bool, motionWorking: Bool = true) -> Bool {
    guard state == .unarmed else {
      return true
    }
    return canAnyTriggerFire(motionEnabled: motionEnabled, cameraAvailable: cameraAvailable,
                             audioEnabled: audioEnabled, audioAvailable: audioAvailable,
                             motionWorking: motionWorking)
  }

  /// Quitting waits only when a file is being written; otherwise it quits at once (spec 0019).
  class func waitsBeforeQuitting(isRecording: Bool) -> Bool {
    return isRecording
  }

  /// Whether OnCue should arm itself after launching: only when the setting is on, nothing is armed
  /// yet, and something could actually fire (spec 0018).
  class func shouldArmAtLaunch(enabled: Bool, state: ArmState, motionEnabled: Bool, cameraAvailable: Bool,
                               audioEnabled: Bool, audioAvailable: Bool) -> Bool {
    return enabled && state == .unarmed
      && canAnyTriggerFire(motionEnabled: motionEnabled, cameraAvailable: cameraAvailable,
                           audioEnabled: audioEnabled, audioAvailable: audioAvailable)
  }

  /// Once nothing can trigger, staying armed only keeps the Mac awake, so disarm.
  /// Detection having stopped is deliberately not a reason to disarm, so `motionWorking` is not a
  /// parameter here. Refusing to Arm happens while someone is standing at the popover and can act;
  /// disarming happens after they have walked away, and a detection outage that recovers seconds
  /// later would leave OnCue unarmed all night with nothing to say so (spec 0030).
  class func shouldAutoDisarm(state: ArmState, motionEnabled: Bool, cameraAvailable: Bool, audioEnabled: Bool, audioAvailable: Bool) -> Bool {
    return state != .unarmed
      && !canAnyTriggerFire(motionEnabled: motionEnabled, cameraAvailable: cameraAvailable,
                            audioEnabled: audioEnabled, audioAvailable: audioAvailable)
  }

  func isArmed() -> Bool {
    armedState! == .armed
  }

  func isRecording() -> Bool {
    armedState! == .recording
  }

  func state() -> ArmState {
    armedState!
  }

  private func arm(_ countdown: Int) {
    refreshArmedRecordOnArm()
    guard countdown > 0 else {
      armedState = .armed
      return
    }
    armingCountdown = countdown
    armedState = .arming
    countdownTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(self.countdown), userInfo: nil, repeats: true)
  }

  /// The record starts with the arming, so a death during the countdown counts too. The
  /// stretch (spec 0054) starts here as well, once per period: an arm while already armed
  /// keeps the start it has.
  private func refreshArmedRecordOnArm() {
    let now = clock()
    ArmedRecord(lastSeen: now, bySchedule: armedBySchedule).write(to: defaults)
    if ArmedStretch.armedSince(in: defaults) == nil {
      ArmedStretch.noteArmed(at: now, in: defaults)
    }
  }

  func startArming(countdown: Int)  {
    #if DEBUG
    if let _ = NSClassFromString("XCTest") {
      arm(countdown)
    } else {
      refreshArmedRecordOnArm()
      armedState = .armed
    }
    #else
    arm(countdown)
    #endif
  }

  func disarm() {
    disarm(keepingNotices: false)
  }

  /// `keepingNotices` leaves the failure and deletion notices standing: a test's own cleanup
  /// (spec 0046). Everything else a disarm clears is cleared either way.
  func disarm(keepingNotices: Bool) {
    countdownTimer?.invalidate()
    let wasRecording = isRecording()
    if isRecordingTest && !keepingNotices {
      // Disarmed by hand mid-test: the test is over, and its files finish as ordinary ones.
      isRecordingTest = false
      testArmedItself = false
      pendingTestFiles = 0
      testDeadline?.cancel()
      testDeadline = nil
    }
    armedState = .unarmed
    armedBySchedule = false
    armedByFocus = false
    ArmedRecord.clear(in: defaults)
    currentFilePaths.removeAll()
    sleptAt = nil
    notWatchingFrom = nil
    notWatchingUntil = nil
    quitUnexpectedlyAt = nil
    quitUnexpectedlyUntil = nil
    if !keepingNotices {
      recordingFailure = nil
      recordingFailureCount = 0
      recordingFailedAt = nil
      deletedCount = 0
      deletedAt = nil
    }
    if wasRecording {
      recorders.forEach { $0.stopRecording() }
    }
  }

  /// Starts a new file on each target, one per camera. Only from `.armed`, so after an interruption
  /// a disarm in between wins.
  func startRecording(to targets: [RecordingTarget]) {
    guard isArmed(), !targets.isEmpty else {
      testRecordingAnswered(started: false)
      return
    }
    // A chosen folder can be on a drive that was unplugged since the last recording, or back after
    // being away. The help says recordings go back to Movies when it isn't there, and this is when
    // OnCue needs it: until now that was only re-read at launch and from Settings, so a folder
    // that went away stayed chosen and every recording failed for the rest of the session.
    fileOutputManager.refreshFolder(RecordingsFolder.current().folder)
    // Stop deliberately rather than write into a full disk and fail (spec 0029). Reported the same
    // way a failed recording is, since from the outside it's the same thing: no footage.
    if let free = fileOutputManager.freeBytes(), !DiskBudget.hasRoomToRecord(freeBytes: free) {
      noteNoRoom()
      testRecordingAnswered(started: false)
      return
    }
    armedState = .recording
    recorders = targets.map { $0.recorder }
    currentTargets = targets
    testRecordingAnswered(started: true)
    stoppingForSpace = false
    for target in targets {
      // Named for when the footage begins, which with pre-roll is before now.
      let url = fileOutputManager.moviePath(cameraName: target.cameraName, microphoneName: target.microphoneName,
                                            date: target.recorder.footageStart)
      currentFilePaths.insert(url.standardizedFileURL.path)
      target.recorder.startRecording(to: url) { [weak self] url, error in
        DispatchQueue.main.async { self?.recordingDidFinish(url: url, error: error) }
      }
    }
  }

  func startRecording(to output: MovieRecorder, cameraName: String? = nil, microphoneName: String? = nil) {
    startRecording(to: [RecordingTarget(recorder: output, cameraName: cameraName, microphoneName: microphoneName)])
  }

  /// Ends every camera's file and returns to armed.
  func stopRecording() {
    guard isRecording() else {
      return
    }
    armedState = .armed
    currentFilePaths.removeAll()
    recorders.forEach { $0.stopRecording() }
  }

  func stopRecording(_ output: MovieRecorder) {
    stopRecording()
  }

  /// Ends a recording in progress ahead of an interruption (camera switch, device lost, session error),
  /// and reports whether there was one to resume once capture is running again.
  func suspendRecording() -> Bool {
    guard isRecording() else {
      return false
    }
    stopRecording()
    return true
  }

  /// A file finished. If it's the one being written and nobody stopped it, it ended on its own
  /// (an error, a full disk, the session stopping), so fall back to armed and let the next trigger
  /// start a new file rather than claim a recording that isn't happening.
  func recordingDidFinish(url: URL, error: Error?) {
    if let error = error {
      print("Recording \(url.lastPathComponent) ended with an error: \(error.localizedDescription)")
    } else {
      // OnCue's own file, kept to its owner even when the folder around it isn't private. Spec
      // 0017 allows a folder anyone with an account on the Mac can read.
      FileOutputManager.makePrivate(url, permissions: 0o600)
    }
    noteOutcome(error)
    if isRecordingTest {
      testFileFinished(url: url, error: error)
    }
    // Compare standardized paths, not URL values: the URL AVFoundation reports back need not be
    // the same value that was handed to it, and `==` on URL answers no for equivalent paths.
    guard isRecording(), currentFilePaths.remove(url.standardizedFileURL.path) != nil else {
      return
    }
    // With two cameras, one file ending on its own leaves the other recording.
    if currentFilePaths.isEmpty {
      armedState = .armed
      // After the files are closed, not before: finishing one cleanly clears the last failure, so
      // noting it earlier would wipe the reason the recording was stopped at all (spec 0031).
      if stoppingForSpace {
        stoppingForSpace = false
        noteNoRoom()
      }
      trimToDiskBudget()
      onRecordingsFinished?()
    }
  }

  /// A finished file's outcome. Both cameras failing is one failure, not two, so a second failure
  /// inside the same recording doesn't count twice.
  private func noteOutcome(_ error: Error?) {
    guard RecordingFailure.isWorthSaying(error), let error = error else {
      if currentFilePaths.isEmpty {
        recordingFailure = nil
        recordingFailureCount = 0
        recordingFailedAt = nil
      }
      return
    }
    let alreadyCounted = recordingFailedAt != nil && !currentFilePaths.isEmpty
    recordingFailure = RecordingFailure.from(error)
    if !alreadyCounted {
      recordingFailureCount += 1
    }
    recordingFailedAt = Date()
  }

  /// No room to start. Counted and shown like a failure, because that's what it is to whoever
  /// comes looking for the footage.
  private func noteNoRoom() {
    recordingFailure = .diskFull
    recordingFailureCount += 1
    recordingFailedAt = Date()
  }

  // MARK: - Keeping the disk promises during a recording (spec 0031)

  private var duringRecordingTimer: Timer?

  /// Spec 0029's two promises were only kept between recordings: free space was read once before
  /// a file opened, and trimming ran only after every file had closed. Recordings are not bounded,
  /// so the case the limit matters most for was the one it didn't cover.
  private func updateDuringRecordingChecks() {
    let recording = armedState == .recording
    if recording, duringRecordingTimer == nil {
      // Thirty seconds is at most 60 MB of overshoot with two cameras, which is 3% of the free
      // space headroom and 6% of the smallest limit anyone can set. Faster would walk the folder
      // the recording is being written to, for nothing.
      let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
        self?.checkDiskDuringRecording()
      }
      RunLoop.main.add(timer, forMode: .common)
      duringRecordingTimer = timer
    } else if !recording {
      duringRecordingTimer?.invalidate()
      duringRecordingTimer = nil
    }
  }

  private func checkDiskDuringRecording() {
    guard armedState == .recording, !stoppingForSpace else { return }

    // Running out of space ends the recording rather than writing until the write fails. That
    // keeps every second already written, where failing loses the tail and leaves a Mac with no
    // room for anything, this included.
    if let free = fileOutputManager.freeBytes(), !DiskBudget.hasRoomToRecord(freeBytes: free) {
      stopForLackOfSpace()
      return
    }

    trimToDiskBudget()

    let limit = DiskBudget.limitBytes(gigabytes: defaults.integer(forKey: "recordingsLimitGB"))
    let inProgress = fileOutputManager.ownRecordings()
      .filter { currentFilePaths.contains($0.url.standardizedFileURL.path) }
      .reduce(Int64(0)) { $0 + $1.bytes }
    if DiskBudget.shouldRoll(inProgressBytes: inProgress, limitBytes: limit) {
      rollRecording()
    }
  }

  /// Ends the recording because the disk is nearly full, finishing the files rather than writing
  /// until a write fails. Why it stopped is reported once they are closed.
  func stopForLackOfSpace() {
    guard armedState == .recording, !stoppingForSpace else { return }
    stoppingForSpace = true
    recorders.forEach { $0.stopRecording() }
  }

  /// Carries the recording on in new files. The ones that close become deletable like any other,
  /// which is what makes the limit true again while an event is still going.
  func rollRecording() {
    for target in currentTargets {
      let url = fileOutputManager.moviePath(cameraName: target.cameraName,
                                            microphoneName: target.microphoneName)
      // Added before the roll is asked for, so the old file finishing doesn't read as the whole
      // recording having ended.
      currentFilePaths.insert(url.standardizedFileURL.path)
      target.recorder.roll(to: url) { [weak self] url, error in
        DispatchQueue.main.async { self?.recordingDidFinish(url: url, error: error) }
      }
    }
  }

  /// Trims OnCue's own recordings back under the rolling window, oldest first. Off unless a limit
  /// is set, and it never touches anything OnCue didn't write (spec 0029).
  ///
  /// `currentFilePaths` holds whatever is open right now, which is two files when two cameras are
  /// recording. It is empty at the only place this runs today, and it is passed anyway so the
  /// guard is real rather than something that would have to be remembered later.
  private func trimToDiskBudget() {
    // Stored in GB, which is what Settings asks for; 0 means the window is off.
    guard let limitBytes = DiskBudget.limitBytes(gigabytes: defaults.integer(forKey: "recordingsLimitGB")) else {
      return
    }
    let deleting = DiskBudget.toDelete(fileOutputManager.ownRecordings(),
                                       limitBytes: limitBytes, keeping: currentFilePaths)
    guard !deleting.isEmpty else { return }
    var removed = 0
    for recording in deleting {
      do {
        try FileManager.default.removeItem(at: recording.url)
        removed += 1
      } catch {
        print("Could not delete \(recording.url.lastPathComponent): \(error.localizedDescription)")
      }
    }
    if removed > 0 {
      deletedCount += removed
      deletedAt = Date()
      print("Deleted \(removed) oldest recording(s) to stay under the limit")
    }
  }

  @objc func countdown() {
    self.willChangeValue(for: \.armedStateRaw)
    armingCountdown -= 1
    self.didChangeValue(for: \.armedStateRaw)

    if armingCountdown == 0 {
      countdownTimer.invalidate()
      armedState = .armed
      if isRecordingTest {
        fireTest()
      }
    }
  }
}
