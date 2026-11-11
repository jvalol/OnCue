//
//  PreRollRecorder.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/19/26.
//  Copyright © 2026 Jake Van Alstyne
//

import AVFoundation

/// Records one camera's compressed video and its mic's audio, keeping the last few seconds in memory
/// so each recording starts before its trigger (spec 0013). Frames arrive compressed from the
/// pipeline; audio arrives as captured and is encoded to AAC as it's written.
final class PreRollRecorder: MovieRecorder {
  private let queue = DispatchQueue(label: "PreRollRecorder")
  private var video = SampleRing<CMSampleBuffer>()
  private var audio = SampleRing<CMSampleBuffer>()
  private var videoFormat: CMFormatDescription?
  private var audioFormat: CMFormatDescription?

  private var writer: AVAssetWriter?
  private var videoInput: AVAssetWriterInput?
  private var audioInput: AVAssetWriterInput?
  private var pendingVideo: [CMSampleBuffer] = []
  private var pendingAudio: [CMSampleBuffer] = []
  /// Set once the first video keyframe (or, with no camera, the first audio) fixes where the file starts.
  private var sessionStart: Double?
  private var stopRequested = false
  private var fileURL: URL?
  private var onFinish: ((URL, Error?) -> Void)?
  /// The newest sample written to the last file, so the next file's pre-roll doesn't repeat it.
  private var lastWritten: Double?
  private var newestWritten: Double?
  /// A roll asked for: finish the open file at the next keyframe and carry on in this one (spec
  /// 0031). Held until that keyframe arrives, then until the old file has actually closed.
  private var rollPending: (url: URL, onFinish: (URL, Error?) -> Void)?

  /// The newest raw frame the pipeline has seen, for the still (spec 0053). The pipeline already
  /// holds this buffer for motion detection, so keeping it here costs the pool nothing more than
  /// one frame of lag.
  private var newestFrame: CVPixelBuffer?
  /// Whether the file being opened is a fresh start, which gets a still, rather than a roll
  /// (spec 0031), which continues the same event and doesn't.
  private var wantsStill = false
  /// The movie a still was written beside, so a file that never happened can take its still with it.
  private var stillBeside: URL?
  private let stillQueue = DispatchQueue(label: "StillWriter", qos: .utility)

  /// What this recording lost, and where (spec 0024). Reset when a file opens.
  private var tally = FrameLoss.Tally()
  private var gaps = FrameLoss.Gaps()
  private var frameInterval: Double = 0

  /// A frame lost somewhere other than here: the pipeline shed it, or the encoder or macOS did.
  func noteDrop(_ reason: FrameLoss.Reason) {
    queue.async { self.tally.record(reason) }
  }

  /// Whether a file is still open. Capture waits for this before stopping (spec 0023), since a
  /// file cut short before `finishWriting` has no index and won't open.
  var isWriting: Bool {
    queue.sync { writer != nil }
  }

  // MARK: - Input

  /// The raw frame behind the next compressed one, kept for the still (spec 0053).
  func noteFrame(_ pixelBuffer: CVPixelBuffer) {
    queue.async { self.newestFrame = pixelBuffer }
  }

  /// A compressed video frame, in capture order.
  func appendVideo(_ sample: CMSampleBuffer) {
    queue.async {
      let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
      let isKeyframe = PreRollRecorder.isKeyframe(sample)
      self.videoFormat = CMSampleBufferGetFormatDescription(sample)
      self.video.append(.init(time: time, isKeyframe: isKeyframe, payload: sample))
      self.trim()
      // A roll waits for a keyframe so the two files meet with nothing between them: this frame
      // ends up beginning the new file rather than being written to the old one. Taken at any
      // other moment it would cost up to a keyframe interval of footage, since a file can only
      // start at a keyframe (spec 0031).
      if isKeyframe, self.rollPending != nil, self.writer != nil, !self.stopRequested {
        self.stopRequested = true
        self.drain()
        return
      }
      self.receiveLive(sample, time: time, isVideo: true)
    }
  }

  /// Carry on recording in a new file, from the next keyframe. The current file is finished the
  /// way any recording is, so what it already holds is kept and reported.
  func roll(to url: URL, onFinish: @escaping (URL, Error?) -> Void) {
    queue.async {
      guard self.writer != nil, !self.stopRequested, self.rollPending == nil else { return }
      self.rollPending = (url: url, onFinish: onFinish)
    }
  }

  /// Captured audio, as it comes from the mic.
  func appendAudio(_ sample: CMSampleBuffer) {
    queue.async {
      let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
      self.audioFormat = CMSampleBufferGetFormatDescription(sample)
      self.audio.append(.init(time: time, isKeyframe: true, payload: sample))
      self.trim()
      self.receiveLive(sample, time: time, isVideo: false)
    }
  }

  /// Drops buffered footage, for a camera or mic change: the old footage no longer matches.
  func reset() {
    queue.async {
      self.video.removeAll()
      self.audio.removeAll()
      self.videoFormat = nil
      self.audioFormat = nil
      self.lastWritten = nil
      self.newestFrame = nil
    }
  }

  private func trim() {
    let window = PreRoll.seconds()
    video.trim(window: window)
    // Video reaches back to the keyframe before the window, up to a second (the keyframe interval)
    // earlier, so keep audio that far back too, or the file's sound would start after its picture.
    audio.trim(window: window + 2)
  }

  private static func isKeyframe(_ sample: CMSampleBuffer) -> Bool {
    guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]],
      let first = attachments.first else { return true }
    return !(first[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)
  }

  // MARK: - MovieRecorder

  var footageStart: Date {
    queue.sync {
      // Against the newest sample from the same ring, never the host clock: the two times have to
      // share a timebase for the gap between them to mean anything.
      guard let start = startTime(), let newest = newestBufferedTime() else { return Date() }
      return PreRoll.date(ofSampleTime: start, newestSampleTime: newest, now: Date())
    }
  }

  /// The newest sample time from whichever ring `startTime` reads, so the two are comparable.
  private func newestBufferedTime() -> Double? {
    return videoFormat != nil ? video.newest : audio.newest
  }

  /// With video, the file starts at a keyframe; with audio only, at the first sample in the window.
  ///
  /// The cutoff comes from the ring's own newest sample, for the same reason trimming does: a
  /// device timestamping ahead of the host clock would otherwise put the cutoff past everything
  /// buffered and start the file at the newest keyframe, quietly giving no pre-roll at all.
  private func startTime() -> Double? {
    let window = PreRoll.seconds()
    if videoFormat != nil {
      guard let cutoff = video.cutoff(window: window) else { return nil }
      return video.startTime(notAfter: cutoff, after: lastWritten)
    }
    guard let cutoff = audio.cutoff(window: window) else { return nil }
    return audio.startTime(notAfter: cutoff, after: lastWritten)
  }

  func startRecording(to url: URL, onFinish: @escaping (URL, Error?) -> Void) {
    queue.async { self.open(url, onFinish: onFinish, still: true) }
  }

  private func open(_ url: URL, onFinish: @escaping (URL, Error?) -> Void, still: Bool) {
    guard self.writer == nil else { return }
    guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else {
      onFinish(url, NSError(domain: AVFoundationErrorDomain, code: AVError.unknown.rawValue))
      return
    }
    // Write an index every two seconds, so a file cut short by a crash, a kill, or a power loss
    // still opens, up to the last flush. Without it an unfinished file has no index at all.
    writer.movieFragmentInterval = CMTime(seconds: 2, preferredTimescale: 1)
    self.writer = writer
    self.fileURL = url
    self.onFinish = onFinish
    self.stopRequested = false
    self.newestWritten = nil
    self.wantsStill = still
    self.stillBeside = nil
    self.tally = FrameLoss.Tally()
    self.gaps = FrameLoss.Gaps()
    self.frameInterval = 0

    if let format = self.videoFormat {
      let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: format)
      input.expectsMediaDataInRealTime = true
      if writer.canAdd(input) { writer.add(input); self.videoInput = input }
    }
    if let format = self.audioFormat, let settings = PreRollRecorder.aacSettings(for: format) {
      let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
      input.expectsMediaDataInRealTime = true
      if writer.canAdd(input) { writer.add(input); self.audioInput = input }
    }
    writer.startWriting()

    // Start from the buffered footage if there is any; otherwise the first live keyframe starts it.
    if let start = self.startTime() {
      self.beginSession(at: start)
    }
  }

  func stopRecording() {
    queue.async {
      guard self.writer != nil else { return }
      self.stopRequested = true
      self.drain()
    }
  }

  // MARK: - Writing

  private func beginSession(at start: Double) {
    guard let writer = writer else { return }
    sessionStart = start
    writer.startSession(atSourceTime: CMTime(seconds: start, preferredTimescale: 1_000_000_000))
    writeStill()
    pendingVideo = videoInput == nil ? [] : video.entries(from: start).map { $0.payload }
    pendingAudio = audioInput == nil ? [] : audio.entries(from: start).map { $0.payload }
    drain()
  }

  /// The still, once the file is really starting (spec 0053): the newest frame in hand, which is
  /// the one that tripped the trigger or the one after it. Encoded off this queue so the first
  /// samples aren't held up behind a JPEG.
  private func writeStill() {
    guard wantsStill, let url = fileURL, let frame = newestFrame else { return }
    wantsStill = false
    stillBeside = url
    stillQueue.async { StillWriter.write(frame, besideMovie: url) }
  }

  private func receiveLive(_ sample: CMSampleBuffer, time: Double, isVideo: Bool) {
    guard writer != nil, !stopRequested else { return }
    if let start = sessionStart {
      guard time >= start else { return }
      if isVideo, videoInput != nil {
        pendingVideo.append(sample)
      } else if !isVideo, audioInput != nil {
        pendingAudio.append(sample)
      }
      drain()
    } else if (isVideo && video.entries.last?.isKeyframe == true) || (!isVideo && videoInput == nil) {
      // Nothing was buffered: the first usable sample starts the file.
      beginSession(at: time)
    }
  }

  /// Appends what each input will take, and finishes the file once a stop was asked for and
  /// everything pending is written.
  private func drain() {
    guard let writer = writer, writer.status == .writing else {
      finishIfStopped()
      return
    }
    drain(&pendingVideo, into: videoInput)
    drain(&pendingAudio, into: audioInput)
    if !pendingVideo.isEmpty || !pendingAudio.isEmpty {
      queue.asyncAfter(deadline: .now() + .milliseconds(10)) { self.drain() }
      return
    }
    finishIfStopped()
  }

  private func drain(_ pending: inout [CMSampleBuffer], into input: AVAssetWriterInput?) {
    guard let input = input else { pending.removeAll(); return }
    let isVideo = input === videoInput
    while let next = pending.first, input.isReadyForMoreMediaData {
      pending.removeFirst()
      let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(next))
      if input.append(next) {
        newestWritten = max(newestWritten ?? time, time)
        if isVideo {
          // Each frame carries its own nominal length, so a camera that isn't 30 fps needs no
          // special case. Keep the last valid one: a sample can arrive without a duration.
          let duration = CMTimeGetSeconds(CMSampleBufferGetDuration(next))
          if duration.isFinite, duration > 0 { frameInterval = duration }
          gaps.wrote(at: time, interval: frameInterval)
        }
      } else if isVideo {
        tally.record(.writerRefused)
      }
    }
  }

  private func finishIfStopped() {
    guard stopRequested, let writer = writer, let url = fileURL else { return }
    let onFinish = self.onFinish
    lastWritten = newestWritten ?? lastWritten
    if sessionStart == nil || writer.status != .writing {
      // Nothing was ever written: no file to keep, and no still without a file.
      writer.cancelWriting()
      try? FileManager.default.removeItem(at: url)
      if let still = stillBeside {
        stillQueue.async { StillWriter.removeStill(besideMovie: still) }
      }
      onFinish?(url, writer.error ?? NSError(domain: AVFoundationErrorDomain, code: AVError.noDataCaptured.rawValue))
    } else {
      videoInput?.markAsFinished()
      audioInput?.markAsFinished()
      let tally = self.tally
      let gaps = self.gaps
      let interval = self.frameInterval
      writer.finishWriting {
        PreRollRecorder.sayWhatWasLost(from: url, tally: tally, gaps: gaps, interval: interval)
        // Reported under the name it was given, whatever it's called now: RecordingManager
        // matches finished recordings by path, and a name it never issued would break the wait
        // that quitting depends on.
        onFinish?(url, writer.error)
      }
    }
    self.writer = nil
    videoInput = nil
    audioInput = nil
    pendingVideo.removeAll()
    pendingAudio.removeAll()
    sessionStart = nil
    fileURL = nil
    self.onFinish = nil
    wantsStill = false
    stillBeside = nil

    // A roll opens its file here rather than where it was asked for, because that is the first
    // moment the old one is actually closed. Draining can take several passes when an input isn't
    // ready, and opening before that would be refused and the roll lost. The keyframe that ended
    // the old file is still in the ring, so the new one begins exactly there (spec 0031).
    if let roll = rollPending {
      rollPending = nil
      open(roll.url, onFinish: roll.onFinish, still: false)
    }
  }

  /// Puts the missing time in the file's name when enough went astray to matter (spec 0024). A
  /// file that lost nothing keeps the name it was given, so a longer name stands out in a folder
  /// precisely because its neighbours don't have one.
  private static func sayWhatWasLost(from url: URL, tally: FrameLoss.Tally, gaps: FrameLoss.Gaps,
                                     interval: Double) {
    let expected = gaps.expected(interval: interval)
    if tally.total > 0 {
      print("\(url.lastPathComponent): \(tally.summary)")
    }
    guard let suffix = FrameLoss.nameSuffix(longest: gaps.longest, missing: gaps.missing,
                                            written: gaps.written, expected: expected) else {
      return
    }
    let renamed = url.deletingLastPathComponent()
      .appendingPathComponent(url.deletingPathExtension().lastPathComponent + suffix)
      .appendingPathExtension(url.pathExtension)
    do {
      try FileManager.default.moveItem(at: url, to: renamed)
    } catch {
      // The recording is the thing that matters; it keeps its original name and the count is
      // still printed above.
      print("Could not rename \(url.lastPathComponent) to say what it lost: \(error.localizedDescription)")
    }
  }

  /// AAC at the captured sample rate, mono or stereo.
  private static func aacSettings(for format: CMFormatDescription) -> [String: Any]? {
    guard let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else { return nil }
    return [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: description.mSampleRate,
      AVNumberOfChannelsKey: min(max(Int(description.mChannelsPerFrame), 1), 2),
      AVEncoderBitRateKey: 128_000,
    ]
  }
}
