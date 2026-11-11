//
//  CameraPipeline.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/19/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import Cocoa
import AVFoundation
import VideoToolbox

protocol CameraPipelineDelegate: AnyObject {
  /// On the detection queue: the motion level for the latest frame, and whether it crossed the trigger.
  func pipeline(_ pipeline: CameraPipeline, measuredMotion level: Double, detected: Bool)
  /// On the video data queue: the frame with motion drawn in, for the preview.
  func pipeline(_ pipeline: CameraPipeline, rendered buffer: CVPixelBuffer)
  /// On any queue: the capture session stopped with an error.
  func pipelineHadRuntimeError(_ pipeline: CameraPipeline, error: Error?)
}

/// One camera's capture: its session, motion detection, and recorder, with the mic added too.
/// Every frame is compressed and every audio sample kept, so the recorder always holds the last few
/// seconds for pre-roll (spec 0013). The owner configures, starts, and stops it on its session queue.
class CameraPipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
  weak var delegate: CameraPipelineDelegate?
  let recorder = PreRollRecorder()
  private(set) var camera: AVCaptureDevice?
  private(set) var microphone: AVCaptureDevice?

  private let session = AVCaptureSession()
  private let videoDataOutput = AVCaptureVideoDataOutput()
  private let audioDataOutput = AVCaptureAudioDataOutput()
  private let audioQueue = DispatchQueue(label: "AudioDataQueue", qos: .userInitiated)
  private var compressionSession: VTCompressionSession?
  private var compressionSize: CMVideoDimensions?
  /// Frames handed to the encoder and not yet returned. The encoder holds each frame's pixel buffer,
  /// which comes from the capture pool, so letting them pile up starves capture: frames stop
  /// arriving and motion detection goes quiet. Skip frames instead; pre-roll loses a frame, not a
  /// second.
  private var framesEncoding = 0
  private let maximumFramesEncoding = 2
  private var motionDetectRenderer = MotionDetectMetalRenderer()
  /// Whether anything is showing the preview (spec 0041). CaptureManager sets it from the preview
  /// window's state; while it's false the kernel writes the mask alone.
  var wantsPreview = false
  private let dataOutputQueue = DispatchQueue(label: "VideoDataQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
  private let detectionQueue = DispatchQueue(label: "DetectionQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
  private var lastSampleBuffer: CMSampleBuffer?
  private var currentSampleBuffer: CMSampleBuffer?
  private let skipPixels = 20

  var isRunning: Bool {
    session.isRunning
  }

  override init() {
    super.init()
    NotificationCenter.default.addObserver(self, selector: #selector(runtimeError(_:)), name: AVCaptureSession.runtimeErrorNotification, object: session)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  /// Replaces the inputs with `camera` and `microphone`, either of which may be nil: with no camera
  /// capture is audio only, with no mic it's video only. Returns false if the outputs couldn't be added.
  func configure(camera: AVCaptureDevice?, microphone: AVCaptureDevice?) -> Bool {
    session.beginConfiguration()
    defer { session.commitConfiguration() }

    // Reconfiguring (e.g. switching cameras) must replace the existing inputs, not add to them.
    for input in session.inputs {
      session.removeInput(input)
    }

    session.sessionPreset = .high

    self.camera = nil
    if let camera = camera,
      let videoInput = try? AVCaptureDeviceInput(device: camera),
      session.canAddInput(videoInput) {
      session.addInput(videoInput)
      self.camera = camera
    } else {
      print("No usable camera, capturing audio only")
    }

    self.microphone = nil
    if let microphone = microphone,
      let audioInput = try? AVCaptureDeviceInput(device: microphone),
      session.canAddInput(audioInput) {
      session.addInput(audioInput)
      self.microphone = microphone
    } else {
      print("No usable audio device, recording video only")
    }

    // Outputs survive reconfiguration, so only add them the first time.
    if !session.outputs.contains(videoDataOutput) {
      guard session.canAddOutput(videoDataOutput) else {
        print("Could not add video data output to the session")
        return false
      }
      session.addOutput(videoDataOutput)
      videoDataOutput.videoSettings = [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        kCVPixelBufferMetalCompatibilityKey as String: true
      ]
      videoDataOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
    }

    if !session.outputs.contains(audioDataOutput) {
      guard session.canAddOutput(audioDataOutput) else {
        print("Could not add audio data output to the session")
        return false
      }
      session.addOutput(audioDataOutput)
      audioDataOutput.setSampleBufferDelegate(self, queue: audioQueue)
    }
    return true
  }

  func start() {
    session.startRunning()
  }

  func stop() {
    session.stopRunning()
  }

  /// Frames from the old camera can differ in size and content from the new one. Drop the
  /// previous frame so the first new frame isn't diffed against it, and re-prepare the renderer
  /// for the new format. Call before restarting; it's queued ahead of any frame from the new session.
  func resetFrames() {
    dataOutputQueue.async {
      self.lastSampleBuffer = nil
      self.currentSampleBuffer = nil
      self.motionDetectRenderer.reset()
      self.endCompression()
    }
    recorder.reset()
  }

  /// The mic's level in dBFS, from the audio output's connection. The loudest channel, so a sound on
  /// one side of a stereo mic still counts. Nil without a mic.
  func microphoneDecibels() -> Double? {
    guard let channels = audioDataOutput.connection(with: .audio)?.audioChannels, !channels.isEmpty else {
      return nil
    }
    return channels.map { Double($0.averagePowerLevel) }.max()
  }

  @objc private func runtimeError(_ notification: Notification) {
    delegate?.pipelineHadRuntimeError(self, error: notification.userInfo?[AVCaptureSessionErrorKey] as? Error)
  }

  // MARK: - Video Data Output Delegate

  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    if output === audioDataOutput {
      recorder.appendAudio(sampleBuffer)
      return
    }
    compress(sampleBuffer)
    if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
      recorder.noteFrame(imageBuffer)
    }
    let last = currentSampleBuffer ?? sampleBuffer
    lastSampleBuffer = last
    currentSampleBuffer = sampleBuffer
    processVideo(lastSampleBuffer: last, currentSampleBuffer: sampleBuffer)
  }

  /// A frame macOS dropped before OnCue ever saw it. Nothing to do about it, but a recording
  /// shouldn't lose frames without anything saying so (spec 0024).
  func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard output !== audioDataOutput else { return }
    recorder.noteDrop(.captureDropped)
  }

  private func processVideo(lastSampleBuffer: CMSampleBuffer, currentSampleBuffer: CMSampleBuffer) {
    guard let lastVideoPixelBuffer = CMSampleBufferGetImageBuffer(lastSampleBuffer),
      let currentVideoPixelBuffer = CMSampleBufferGetImageBuffer(currentSampleBuffer),
      let formatDescription = CMSampleBufferGetFormatDescription(lastSampleBuffer) else {
        return
    }

    if !motionDetectRenderer.isPrepared {
      /*
       outputRetainedBufferCountHint is the number of pixel buffers the renderer retains. This value informs the renderer
       how to size its buffer pool and how many pixel buffers to preallocate. Allow 3 frames of latency to cover the dispatch_async call.
       */
      motionDetectRenderer.prepare(with: formatDescription, outputRetainedBufferCountHint: 3)
    }

    // One pass, two buffers (spec 0040): the mask is what the sampler counts, the preview is what
    // the window shows. Keeping them apart is what lets the picture change without the meter moving.
    guard let (maskBuffer, previewBuffer) = motionDetectRenderer.renderWithPreview(lastPixelBuffer: lastVideoPixelBuffer, currentPixelBuffer: currentVideoPixelBuffer,
                                                                                    preview: wantsPreview) else {
      print("Unable to filter video buffer")
      return
    }

    detectionQueue.async {
      CVPixelBufferLockBaseAddress(maskBuffer, .readOnly)
      let (level, detected) = self.measureMotion(pixelBuffer: maskBuffer)
      CVPixelBufferUnlockBaseAddress(maskBuffer, .readOnly)
      self.delegate?.pipeline(self, measuredMotion: level, detected: detected)
    }

    if let previewBuffer = previewBuffer {
      delegate?.pipeline(self, rendered: previewBuffer)
    }
  }

  // MARK: - Compression

  /// H.264 in real time, a keyframe every second so pre-roll can start close to its length, and no
  /// frame reordering so frames can go straight into the file in capture order.
  private func compress(_ sampleBuffer: CMSampleBuffer) {
    guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    let size = CMVideoDimensions(width: Int32(CVPixelBufferGetWidth(imageBuffer)), height: Int32(CVPixelBufferGetHeight(imageBuffer)))
    if compressionSession == nil || compressionSize?.width != size.width || compressionSize?.height != size.height {
      endCompression()
      var session: VTCompressionSession?
      guard VTCompressionSessionCreate(allocator: nil, width: size.width, height: size.height, codecType: kCMVideoCodecType_H264,
                                       encoderSpecification: nil, imageBufferAttributes: nil, compressedDataAllocator: nil,
                                       outputCallback: nil, refcon: nil, compressionSessionOut: &session) == noErr,
        let created = session else {
        print("Could not create the video compressor")
        return
      }
      VTSessionSetProperty(created, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
      VTSessionSetProperty(created, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
      VTSessionSetProperty(created, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
      VTSessionSetProperty(created, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: 1.0 as CFNumber)
      VTSessionSetProperty(created, key: kVTCompressionPropertyKey_AverageBitRate,
                           value: TriggerCost.assumedBitsPerSecond as CFNumber)
      VTSessionSetProperty(created, key: kVTCompressionPropertyKey_MaxFrameDelayCount, value: 1 as CFNumber)
      compressionSession = created
      compressionSize = size
    }
    guard let session = compressionSession else { return }
    guard framesEncoding < maximumFramesEncoding else {
      // Shedding on purpose: letting the encoder fall further behind would hold capture buffers
      // until the pool starves. Counted, because a recording that quietly loses frames is worse
      // than one that says so (spec 0024).
      recorder.noteDrop(.encoderBehind)
      return
    }
    framesEncoding += 1
    let recorder = self.recorder
    VTCompressionSessionEncodeFrame(session, imageBuffer: imageBuffer,
                                    presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
                                    duration: CMSampleBufferGetDuration(sampleBuffer), frameProperties: nil,
                                    infoFlagsOut: nil) { [weak self] status, _, compressed in
      self?.dataOutputQueue.async { self?.framesEncoding -= 1 }
      guard status == noErr, let compressed = compressed else {
        recorder.noteDrop(.encodeFailed)
        return
      }
      recorder.appendVideo(compressed)
    }
  }

  private func endCompression() {
    if let session = compressionSession {
      VTCompressionSessionInvalidate(session)
    }
    compressionSession = nil
    compressionSize = nil
    framesEncoding = 0
  }

  private func measureMotion(pixelBuffer: CVPixelBuffer) -> (level: Double, detected: Bool) {
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)

    // The zones decide which sampled pixels count, and are the universe the level is a fraction
    // of (spec 0042). With none drawn, every sampled pixel counts, as it always did.
    let zones = DetectionZones.current(cameraID: camera?.uniqueID)
    let (pixelsTested, pixelsWithMotion) = zones.count(width: width, height: height, stride: skipPixels) { x, y in
      let (r, g, b) = pixelFrom(x: x, y: y, pixelBuffer: pixelBuffer)
      let marked = g == 0 && b == 0 && r > 0
      #if DEBUG
      if marked { recordMagnitude(red: r) }
      #endif
      return marked
    }
    #if DEBUG
    writeMagnitudes()
    #endif

    let threshold = MotionDetector.threshold(cameraID: camera?.uniqueID)
    return (MotionDetector.motionLevel(pixelsWithMotion: pixelsWithMotion, pixelsTested: pixelsTested),
            MotionDetector.detectMotion(pixelsWithMotion: pixelsWithMotion, pixelsTested: pixelsTested, threshold: threshold))
  }

  #if DEBUG
  // Debug builds only, and only with ONCUE_MEASURE set (see MotionDetectMetalRenderer): how big
  // the changes are among the sampled pixels the mask marks. The mask's red is
  // 1.5 × (deltaDotP − 1) clamped to 1, so a red byte maps back to deltaDotP up to 1.667 and
  // saturates past it. Five bins, cumulative, written every 300 frames. For the question 0040
  // pinned: whether there's any room to grade the overlay by magnitude.
  private var magnitudeBins = [Int](repeating: 0, count: 5)
  private var magnitudeFrames = 0
  private static let measurePath = ProcessInfo.processInfo.environment["ONCUE_MEASURE"]

  private func recordMagnitude(red: UInt8) {
    guard CameraPipeline.measurePath != nil else { return }
    // deltaDotP 1.2–1.3 → red 77–114, 1.3–1.4 → 115–152, 1.4–1.5 → 153–190, 1.5–1.667 → 191–254.
    let bin: Int
    switch red {
    case ..<115: bin = 0
    case ..<153: bin = 1
    case ..<191: bin = 2
    case ..<255: bin = 3
    default: bin = 4
    }
    magnitudeBins[bin] += 1
  }

  private func writeMagnitudes() {
    guard let path = CameraPipeline.measurePath else { return }
    magnitudeFrames += 1
    guard magnitudeFrames % 300 == 0 else { return }
    let total = magnitudeBins.reduce(0, +)
    let line = String(format: "magnitude: %d marked samples over %d frames: 1.2-1.3 %d, 1.3-1.4 %d, 1.4-1.5 %d, 1.5-1.67 %d, >=1.67 %d\n",
                      total, magnitudeFrames, magnitudeBins[0], magnitudeBins[1], magnitudeBins[2], magnitudeBins[3], magnitudeBins[4])
    if let handle = FileHandle(forWritingAtPath: path) ?? (FileManager.default.createFile(atPath: path, contents: nil) ? FileHandle(forWritingAtPath: path) : nil) {
      handle.seekToEndOfFile(); handle.write(line.data(using: .utf8)!); handle.closeFile()
    }
  }
  #endif

  private func pixelFrom(x: Int, y: Int, pixelBuffer: CVPixelBuffer) -> (UInt8, UInt8, UInt8) {
    let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let buffer = baseAddress!.assumingMemoryBound(to: UInt8.self)

    let index = x*4 + y*bytesPerRow
    let b = buffer[index]
    let g = buffer[index+1]
    let r = buffer[index+2]

    return (r, g, b)
  }
}
