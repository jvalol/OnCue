//
//  CaptureManager.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 2/15/20.
//  Copyright © 2020 Jake Van Alstyne. All rights reserved.
//

import Cocoa
import AVFoundation
import CoreAudio

protocol CaptureManagerPreviewDelegate {
  /// The first camera's aspect ratio.
  func setAspectRatio(_ ratio: CGSize)
  /// Called on the main queue whenever capture is configured: the cameras in use, in order, empty
  /// while capture is audio only.
  func setCameraNames(_ names: [String])
  /// A frame from camera 0 (the first) or 1 (the second).
  func setPreviewBuffer(_ buffer: CVPixelBuffer, camera: Int)
}

protocol CaptureManagerActivityDelegate {
  /// The motion level from camera 0 (the first) or 1 (the second).
  func motionActivityReported(activity: Double, camera: Int)
  func soundActivityReported(level: Double)
  /// Called on the main queue whenever the session is configured, with nil for a missing device.
  func devicesChanged(cameraName: String?, secondCameraName: String?, microphoneName: String?)
  /// Whether each camera's motion detection has stopped measuring, by camera index (spec 0030).
  func motionDetectionChanged(stopped: [Bool])
}

protocol CaptureManagerSettingsDelegate {

}

class CaptureManager: NSObject, CameraPipelineDelegate {
  var previewDelegate: CaptureManagerPreviewDelegate!
  var activityDelegate: CaptureManagerActivityDelegate!
  var settingsDelegate: CaptureManagerSettingsDelegate!
  var videoCaptureDevices: [AVCaptureDevice]! {
    get {
      AVCaptureDevice.DiscoverySession.init(deviceTypes: [.builtInWideAngleCamera, .external], mediaType: .video, position: .front).devices.filter { (device) -> Bool in
        device.isConnected == true && device.isSuspended == false
      }
    }
  }
  var defaultVideoCaptureDevice: AVCaptureDevice? {
    get {
      videoCaptureDevices.first
    }
  }
  /// The camera picked in Settings if it's connected, otherwise the first available.
  var preferredVideoCaptureDevice: AVCaptureDevice? {
    DevicePreference.preferred(savedID: UserDefaults.standard.string(forKey: "selectedCameraID"),
                               available: videoCaptureDevices) { $0.uniqueID }
  }
  var audioCaptureDevices: [AVCaptureDevice]! {
    get {
      AVCaptureDevice.DiscoverySession.init(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices.filter { (device) -> Bool in
        device.isConnected == true && device.isSuspended == false
      }
    }
  }
  var defaultAudioCaptureDevice: AVCaptureDevice? {
    get {
      audioCaptureDevices.first
    }
  }
  /// The mic picked in Settings if it's connected, otherwise the input chosen in macOS Sound
  /// settings. With no mic picked, OnCue follows the system input.
  var preferredAudioCaptureDevice: AVCaptureDevice? {
    DevicePreference.preferred(savedID: UserDefaults.standard.string(forKey: "selectedMicrophoneID"),
                               available: audioCaptureDevices,
                               fallback: AVCaptureDevice.default(for: .audio)) { $0.uniqueID }
  }

  /// The second camera chosen in Settings, if it's connected and isn't the first camera.
  var preferredSecondVideoCaptureDevice: AVCaptureDevice? {
    secondCamera(besides: preferredVideoCaptureDevice)
  }

  var aspectRatio: CGSize!
  var currentVideoCaptureDevice: AVCaptureDevice? { pipeline.camera }
  var currentSecondVideoCaptureDevice: AVCaptureDevice? { secondPipeline.camera }
  var currentAudioCaptureDevice: AVCaptureDevice? { pipeline.microphone }

  /// One pipeline per camera: the first camera, and an optional second (spec 0012).
  private let pipelines = [CameraPipeline(), CameraPipeline()]
  private var pipeline: CameraPipeline { pipelines[0] }
  private var secondPipeline: CameraPipeline { pipelines[1] }
  private let sessionQueue = DispatchQueue(label: "SessionQueue", attributes: [], autoreleaseFrequency: .workItem)
  private let audioMeterQueue = DispatchQueue(label: "AudioMeterQueue", qos: .userInitiated)
  private var audioMeterTimer: DispatchSourceTimer?
  private var stopTecordingTask: DispatchWorkItem?
  /// Whether capture is running now, and the retry waiting on a file to finish writing.
  private var capturing = false
  private var pendingStop: DispatchWorkItem?
  private var armStateObservation: NSKeyValueObservation?

  private enum SessionSetupResult {
    case success
    case notAuthorized
    case configurationFailed
  }

  private var setupResult: SessionSetupResult = .success

  override init() {
    super.init()
    pipelines.forEach { $0.delegate = self }

    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      break

    case .notDetermined:
      sessionQueue.suspend()
      AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
        if !granted {
          self.setupResult = .notAuthorized
        }
        self.sessionQueue.resume()
      })

    default:
      setupResult = .notAuthorized
    }

    sessionQueue.async {
      let camera = self.preferredVideoCaptureDevice
      self.configureSession(video: camera, secondVideo: self.secondCamera(besides: camera), audio: self.preferredAudioCaptureDevice)
    }

    sessionQueue.async {
      switch self.setupResult {
      case .success:
        // Configured but not started: capture waits for something to need it (spec 0023).
        DispatchQueue.main.async { self.updateCapture() }
      case .notAuthorized:
        NSLog("Not authorized")
      case .configurationFailed:
        NSLog("Configuration failed")
      }
    }

    // On the main queue rather than here: RecordingManager is a sibling static, so it isn't
    // necessarily built yet while this initialiser is running.
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.armStateObservation = AppDelegate.recordingManager.observe(\.armedStateRaw) { [weak self] _, _ in
        DispatchQueue.main.async { self?.updateCapture() }
      }
      self.updateCapture()
    }

    NotificationCenter.default.addObserver(self, selector: #selector(self.stopRecording), name: NSApplication.willTerminateNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(self.deviceWasDisconnected(_:)), name: AVCaptureDevice.wasDisconnectedNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(self.deviceWasConnected(_:)), name: AVCaptureDevice.wasConnectedNotification, object: nil)
    followSystemInput()
  }

  deinit {
    // Capture the pipelines rather than self, which is gone by the time the block runs.
    guard setupResult == .success else { return }
    let pipelines = self.pipelines
    sessionQueue.async {
      pipelines.forEach { $0.stop() }
    }
  }

  /// The user picked a camera in Settings, or nil for no camera at all: remember it, and switch.
  /// A single camera is always the first one, so choosing none clears the second as well.
  func changeVideoCaptureDevice(_ captureDevice: AVCaptureDevice?) {
    UserDefaults.standard.set(captureDevice?.uniqueID ?? DevicePreference.noDevice, forKey: "selectedCameraID")
    if captureDevice == nil {
      UserDefaults.standard.set(nil, forKey: "secondCameraID")
    }
    setTriggerEnabled("motionTriggerEnabled", choosingNone: captureDevice == nil)
    recoverFromInterruption {
      self.reconfigure(camera: captureDevice)
    }
  }

  /// The user picked a second camera in Settings, or nil for none: remember it, and switch.
  func changeSecondVideoCaptureDevice(_ device: AVCaptureDevice?) {
    UserDefaults.standard.set(device?.uniqueID, forKey: "secondCameraID")
    recoverFromInterruption {
      self.reconfigure(camera: self.currentVideoCaptureDevice)
    }
  }

  private func secondCamera(besides first: AVCaptureDevice?) -> AVCaptureDevice? {
    DevicePreference.second(savedID: UserDefaults.standard.string(forKey: "secondCameraID"),
                            available: videoCaptureDevices, firstID: first?.uniqueID) { $0.uniqueID }
  }

  /// The user picked a mic in Settings, or nil to follow the system input: remember it, and switch.
  func changeAudioCaptureDevice(_ device: AVCaptureDevice?) {
    UserDefaults.standard.set(device?.uniqueID, forKey: "selectedMicrophoneID")
    recoverFromInterruption {
      self.reconfigure(camera: self.currentVideoCaptureDevice)
    }
  }

  /// The user chose no microphone at all, which is a different thing from not having picked one:
  /// nil follows the system input, `noDevice` means none (spec 0028).
  func chooseNoAudioCaptureDevice() {
    UserDefaults.standard.set(DevicePreference.noDevice, forKey: "selectedMicrophoneID")
    setTriggerEnabled("audioTriggerEnabled", choosingNone: true)
    recoverFromInterruption {
      self.reconfigure(camera: self.currentVideoCaptureDevice)
    }
  }

  /// Choosing no device switches off the trigger that depended on it. Only a choice comes through
  /// here; a device going missing leaves its trigger alone.
  private func setTriggerEnabled(_ key: String, choosingNone: Bool) {
    let defaults = UserDefaults.standard
    defaults.set(DevicePreference.triggerEnabled(wasEnabled: defaults.bool(forKey: key),
                                                 choosingNone: choosingNone), forKey: key)
  }

  /// While following the system input, switch mics when it changes in macOS Sound settings.
  private func followSystemInput() {
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                             mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
    let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, sessionQueue) { [weak self] _, _ in
      guard let self = self, UserDefaults.standard.string(forKey: "selectedMicrophoneID") == nil,
        let systemInput = AVCaptureDevice.default(for: .audio),
        systemInput != self.currentAudioCaptureDevice else { return }
      print("System input changed to \(systemInput.localizedName), switching to it")
      self.recoverFromInterruption {
        self.reconfigure(camera: self.currentVideoCaptureDevice)
      }
    }
    if status != noErr {
      print("Could not follow the system input: \(status)")
    }
  }

  @objc private func deviceWasDisconnected(_ notification: Notification) {
    guard let device = notification.object as? AVCaptureDevice else { return }
    sessionQueue.async {
      guard device == self.currentVideoCaptureDevice || device == self.currentSecondVideoCaptureDevice
        || device == self.currentAudioCaptureDevice else { return }
      print("Lost \(device.localizedName), reconfiguring with what's left")
      self.recoverFromInterruption {
        // Keep the camera in use if it's still there (the lost device may have been the mic);
        // otherwise the chosen camera if connected, else the first one left, if any.
        let camera = self.currentVideoCaptureDevice.flatMap { $0.isConnected ? $0 : nil } ?? self.preferredVideoCaptureDevice
        self.reconfigure(camera: camera)
      }
    }
  }

  /// A camera or mic connected. Use it if capture has none of that kind, or if it's the chosen
  /// camera coming back while capture is on a fallback. Otherwise leave capture alone.
  @objc private func deviceWasConnected(_ notification: Notification) {
    guard let device = notification.object as? AVCaptureDevice else { return }
    sessionQueue.async {
      guard self.setupResult != .notAuthorized else { return }
      if device.hasMediaType(.video), self.currentSecondVideoCaptureDevice == nil,
        device.uniqueID == UserDefaults.standard.string(forKey: "secondCameraID"),
        device.uniqueID != self.currentVideoCaptureDevice?.uniqueID {
        print("\(device.localizedName) connected, adding it as the second camera")
        self.recoverFromInterruption {
          self.reconfigure(camera: self.currentVideoCaptureDevice)
        }
      } else if device.hasMediaType(.video) {
        guard DevicePreference.shouldSwitch(toConnectedID: device.uniqueID,
                                            currentID: self.currentVideoCaptureDevice?.uniqueID,
                                            savedID: UserDefaults.standard.string(forKey: "selectedCameraID")) else { return }
        print("\(device.localizedName) connected, switching to it")
        self.recoverFromInterruption {
          self.reconfigure(camera: device)
        }
      } else if device.hasMediaType(.audio),
        DevicePreference.shouldSwitch(toConnectedID: device.uniqueID,
                                      currentID: self.currentAudioCaptureDevice?.uniqueID,
                                      savedID: UserDefaults.standard.string(forKey: "selectedMicrophoneID")) {
        print("\(device.localizedName) connected, switching to it")
        self.recoverFromInterruption {
          self.reconfigure(camera: self.currentVideoCaptureDevice)
        }
      }
    }
  }

  func pipelineHadRuntimeError(_ pipeline: CameraPipeline, error: Error?) {
    print("Capture session error, restarting: \(error?.localizedDescription ?? "unknown")")
    recoverFromInterruption {
      self.stop()
      self.start()
    }
  }

  /// Ends any recording in progress, runs `restart` on the session queue, then starts a new file
  /// if one was cut short and capture is running again. RecordingManager only starts a file from
  /// `.armed`, so a disarm in between, including an automatic one for lost devices, wins.
  private func recoverFromInterruption(_ restart: @escaping () -> Void) {
    DispatchQueue.main.async {
      let wasRecording = AppDelegate.recordingManager.suspendRecording()
      self.sessionQueue.async {
        guard self.setupResult != .notAuthorized else { return }
        restart()
        guard wasRecording, self.pipelines.contains(where: { $0.isRunning }) else { return }
        DispatchQueue.main.async {
          self.startRecording()
        }
      }
    }
  }

  /// Rebuilds capture around `camera` (nil for audio only) and the preferred mic. Session queue only.
  private func reconfigure(camera: AVCaptureDevice?) {
    self.stop()
    self.pipelines.forEach { $0.resetFrames() }

    self.setupResult = .success
    self.configureSession(video: camera, secondVideo: self.secondCamera(besides: camera), audio: self.preferredAudioCaptureDevice)
    if self.setupResult == .success {
      // Only start again if something still needs capture; a device change while idle just
      // reconfigures (spec 0023).
      if self.capturing { self.start() }
    } else {
      NSLog("Configuration failed")
    }
  }

  /// Starts the first pipeline, and the second only if it has a camera.
  private func start() {
    pipeline.start()
    if secondPipeline.camera != nil {
      secondPipeline.start()
    }
  }

  private func stop() {
    pipelines.forEach { $0.stop() }
  }

  // MARK: - When capture runs (spec 0023)

  /// The popover is open. Set by the popover's own delegate, so a close it refuses doesn't count.
  var popoverOpen = false { didSet { updateCapture() } }
  /// The preview window is on screen. Also what tells each pipeline whether to draw the preview
  /// picture at all (spec 0041).
  var previewOpen = false {
    didSet {
      for pipeline in pipelines { pipeline.wantsPreview = previewOpen }
      updateCapture()
    }
  }

  /// Whether a recording is still being written, which delays a stop however little else needs it.
  private var writingFiles: Bool { pipelines.contains { $0.recorder.isWriting } }

  /// Re-decides whether capture should be running. Called whenever a reason changes: the arm
  /// state, the popover, the preview window. Main queue, so the arm state is read consistently.
  func updateCapture() {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { self.updateCapture() }
      return
    }
    guard setupResult == .success else { return }
    let wanted = CaptureDemand.shouldCapture(armState: AppDelegate.recordingManager.state(),
                                             popoverOpen: popoverOpen, previewOpen: previewOpen)
    if wanted {
      pendingStop?.cancel()
      pendingStop = nil
      guard !capturing else { return }
      capturing = true
      startMotionHealth()
      sessionQueue.async {
        self.start()
        self.startAudioMeter()
      }
    } else {
      guard capturing, pendingStop == nil else { return }
      stopWhenFilesAreDone()
    }
  }

  // MARK: - Whether motion is being measured (spec 0030)

  /// When each camera last reported a measurement, and whether it is currently counted as stopped.
  /// Main queue only, which is where the timer runs and where measurements are noted.
  private var lastMotionMeasured: [Date?] = [nil, nil]
  private var motionStopped: [Bool] = [false, false]
  private var motionHealthTimer: Timer?
  /// Frames measured per camera since capture started. A recorder opened before its camera has
  /// produced a frame has no video format and writes an audio-only file, so a test waits for at
  /// least one frame from every running camera (found on 2026-09-23: two audio-only files).
  private var framesSeen: [Int] = [0, 0]
  private var testWaitsForFrames = false

  /// A camera measured something. What it measured doesn't matter: a level of zero from a camera
  /// pointed at a wall is a working camera, and the only thing that says detection died is
  /// measurements not arriving at all.
  private func noteMotionMeasured(camera: Int) {
    let now = Date()
    framesSeen[camera] += 1
    fireTestIfWaitingForFrames()
    let wasStopped = motionStopped[camera]
    if wasStopped, let outage = MotionHealth.outage(from: lastMotionMeasured[camera], to: now) {
      // The warning goes, but the stretch with no footage in it stays, the same way a sleep gap
      // does. Whoever was away needs to know there is a hole, not just that it's over.
      AppDelegate.recordingManager.noteNotWatching(from: outage.from, to: outage.to)
    }
    lastMotionMeasured[camera] = now
    motionStopped[camera] = false
    if wasStopped { reportMotionHealth() }
  }

  private func startMotionHealth() {
    guard motionHealthTimer == nil else { return }
    lastMotionMeasured = pipelines.map { _ in Date() }
    motionStopped = pipelines.map { _ in false }
    framesSeen = pipelines.map { _ in 0 }
    // Once a second against a five second window: late enough to be cheap, often enough that the
    // warning lands while someone who just armed it is still standing there.
    let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
      self?.checkMotionHealth()
    }
    RunLoop.main.add(timer, forMode: .common)
    motionHealthTimer = timer
  }

  private func stopMotionHealth() {
    motionHealthTimer?.invalidate()
    motionHealthTimer = nil
    lastMotionMeasured = pipelines.map { _ in nil }
    motionStopped = pipelines.map { _ in false }
    reportMotionHealth()
  }

  private func checkMotionHealth() {
    let now = Date()
    var changed = false
    for camera in pipelines.indices where pipelines[camera].camera != nil {
      let stopped = MotionHealth.stopped(capturing: capturing, lastMeasured: lastMotionMeasured[camera], now: now)
      if stopped != motionStopped[camera] {
        motionStopped[camera] = stopped
        changed = true
      }
    }
    if changed { reportMotionHealth() }
  }

  private func reportMotionHealth() {
    let stopped = motionStopped
    AppDelegate.recordingManager.motionDetectionChanged(stopped: stopped.contains(true))
    activityDelegate?.motionDetectionChanged(stopped: stopped)
  }

  /// Stops capture once nothing needs it and no file is still open. Disarming during a recording
  /// clears the arm state before the files finish, so this waits rather than cutting them short.
  private func stopWhenFilesAreDone() {
    guard CaptureDemand.canStop(shouldCapture: false, writingFiles: writingFiles) else {
      let task = DispatchWorkItem { [weak self] in
        self?.pendingStop = nil
        self?.updateCapture()
      }
      pendingStop = task
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200), execute: task)
      return
    }
    capturing = false
    stopAudioMeter()
    stopMotionHealth()
    sessionQueue.async { self.stop() }
  }

  /// Either device may be missing: with no camera capture is audio only, with no mic it's video only.
  /// The mic goes into both pipelines, so both cameras' recordings carry sound (spec 0012 trial).
  private func configureSession(video videoDevice: AVCaptureDevice?, secondVideo secondVideoDevice: AVCaptureDevice?,
                                audio audioDevice: AVCaptureDevice?) {
    if setupResult != .success {
      return
    }

    var outputsAdded = pipeline.configure(camera: videoDevice, microphone: audioDevice)
    if let second = secondVideoDevice {
      outputsAdded = secondPipeline.configure(camera: second, microphone: audioDevice) && outputsAdded
    } else {
      _ = secondPipeline.configure(camera: nil, microphone: nil)
    }

    if let camera = pipeline.camera {
      let dimensions = CMVideoFormatDescriptionGetDimensions(camera.activeFormat.formatDescription)
      let aspectRatio = CGSize(width: CGFloat(dimensions.width), height: CGFloat(dimensions.height))
      // Kept, not only sent: a preview window opened after capture is already running reads this
      // when it loads, and without it the window was never sized to two cameras.
      self.aspectRatio = aspectRatio
      DispatchQueue.main.async {
        guard let delegate = self.previewDelegate else { return }
        delegate.setAspectRatio(aspectRatio)
      }
    }

    reportDevices(camera: pipeline.camera, secondCamera: secondPipeline.camera, microphone: pipeline.microphone)
    let cameraNames = pipelines.compactMap { $0.camera?.localizedName }
    DispatchQueue.main.async {
      self.previewDelegate?.setCameraNames(cameraNames)
    }

    if !outputsAdded {
      setupResult = .configurationFailed
    }
  }
}

extension CaptureManager {
  // MARK: - Camera pipeline

  func pipeline(_ pipeline: CameraPipeline, measuredMotion level: Double, detected: Bool) {
    if detected {
      activityDetected()
    }
    let camera = index(of: pipeline)
    DispatchQueue.main.async { self.noteMotionMeasured(camera: camera) }
    activityDelegate.motionActivityReported(activity: level, camera: camera)
  }

  func pipeline(_ pipeline: CameraPipeline, rendered buffer: CVPixelBuffer) {
    previewDelegate?.setPreviewBuffer(buffer, camera: index(of: pipeline))
  }

  private func index(of pipeline: CameraPipeline) -> Int {
    pipelines.firstIndex { $0 === pipeline } ?? 0
  }
}

extension CaptureManager {
  // MARK: - Audio level

  private func reportDevices(camera: AVCaptureDevice?, secondCamera: AVCaptureDevice?, microphone: AVCaptureDevice?) {
    let cameraName = camera?.localizedName
    let secondCameraName = secondCamera?.localizedName
    let microphoneName = microphone?.localizedName
    DispatchQueue.main.async {
      // Motion can fire while either camera is there.
      AppDelegate.recordingManager.deviceAvailabilityChanged(camera: cameraName != nil || secondCameraName != nil,
                                                             microphone: microphoneName != nil)
      self.activityDelegate?.devicesChanged(cameraName: cameraName, secondCameraName: secondCameraName, microphoneName: microphoneName)
    }
  }

  /// Samples the microphone level ten times a second.
  private func stopAudioMeter() {
    audioMeterTimer?.cancel()
    audioMeterTimer = nil
    activityDelegate?.soundActivityReported(level: 0)
  }

  private func startAudioMeter() {
    guard audioMeterTimer == nil else { return }
    let timer = DispatchSource.makeTimerSource(queue: audioMeterQueue)
    timer.schedule(deadline: .now(), repeating: .milliseconds(100))
    timer.setEventHandler { [weak self] in
      self?.measureAudio()
    }
    timer.resume()
    audioMeterTimer = timer
  }

  private func measureAudio() {
    guard let decibels = pipeline.microphoneDecibels() else {
      return
    }
    let level = AudioDetector.level(decibels: decibels)
    activityDelegate?.soundActivityReported(level: level)

    let defaults = UserDefaults.standard
    if AudioDetector.detectSound(level: level,
                                 threshold: defaults.double(forKey: "audioTriggerThreshold"),
                                 enabled: defaults.bool(forKey: "audioTriggerEnabled")) {
      activityDetected()
    }
  }
}

extension CaptureManager {
  /// Motion or sound crossed its threshold: start recording if armed, or keep an in-progress recording going.
  private func activityDetected() {
    DispatchQueue.main.async {
      if AppDelegate.recordingManager.isArmed() {
        self.startRecording()
      } else if AppDelegate.recordingManager.isRecording() {
        self.scheduleStopRecording()
      }
    }
  }

  /// A test recording (spec 0046): the trigger's path, started by hand. From unarmed with the
  /// popover closed the cameras are only now starting, so the start waits for their frames; the
  /// manager hears the answer through `startRecording(to:)` either way, or its deadline ends
  /// the test if no frame ever comes.
  func recordTestNow() {
    guard AppDelegate.recordingManager.isArmed() else { return }
    if videoFlowingOnEveryRunningCamera() {
      startRecording()
      return
    }
    testWaitsForFrames = true
    updateCapture()
  }

  /// Every running camera has measured a frame. With no camera at all (sound only), any running
  /// pipeline will do.
  private func videoFlowingOnEveryRunningCamera() -> Bool {
    let withCamera = pipelines.indices.filter { pipelines[$0].isRunning && pipelines[$0].camera != nil }
    guard !withCamera.isEmpty else { return pipelines.contains { $0.isRunning } }
    return withCamera.allSatisfy { framesSeen[$0] > 0 }
  }

  private func fireTestIfWaitingForFrames() {
    guard testWaitsForFrames else { return }
    let manager = AppDelegate.recordingManager
    guard manager.isArmed(), manager.isRecordingTest else {
      testWaitsForFrames = false
      return
    }
    guard videoFlowingOnEveryRunningCamera() else { return }
    testWaitsForFrames = false
    startRecording()
  }

  /// Any trigger records on every running camera (spec 0012).
  private func startRecording() {
    let states = pipelines.map { (running: $0.isRunning, hasCamera: $0.camera != nil, hasMicrophone: $0.microphone != nil) }
    let targets = DevicePreference.recordingPipelines(states).map { index -> RecordingTarget in
      let pipeline = pipelines[index]
      return RecordingTarget(recorder: pipeline.recorder,
                             cameraName: pipeline.camera?.localizedName,
                             microphoneName: pipeline.microphone?.localizedName)
    }
    AppDelegate.recordingManager.startRecording(to: targets)
    self.scheduleStopRecording()
  }

  @objc private func stopRecording() {
    AppDelegate.recordingManager.stopRecording()
  }

  private func scheduleStopRecording() {
    stopTecordingTask?.cancel()

    let task = DispatchWorkItem { [weak self] in
      self?.stopRecording()
    }

    stopTecordingTask = task
    // Settings holds the timeout to 0 through 600 seconds; a value saved before that cap is held to it too.
    let timeout = min(max(UserDefaults.standard.integer(forKey: "timeoutValueInSeconds"), 0), 600)
    let dispatchAfter = DispatchTimeInterval.seconds(timeout)
    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + dispatchAfter,
                                  execute: task)
  }
}
