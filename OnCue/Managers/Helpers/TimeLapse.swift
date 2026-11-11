//
//  TimeLapse.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/30/26.
//  Copyright © 2026 Jake Van Alstyne
//

import Foundation
import AVFoundation
import CoreGraphics
import CoreText
import ImageIO

/// A stretch's story as one short movie (spec 0055): each recording's still, then a frame every
/// two seconds of it, in time order across both cameras, each held a quarter of a second with
/// the time in the corner. `TimeLapse` is the plan and the drawing, pure and tested;
/// `TimeLapseRenderer` reads the files and writes the movie.
enum TimeLapse {
  /// Seconds of footage between samples of a recording.
  static let step: Double = 2
  /// Seconds each frame is shown: four a second, eight times speed at the sampling step.
  static let hold: Double = 0.25
  static let framesPerSecond: Int32 = 4

  struct Frame: Equatable {
    enum Source: Equatable {
      case still(URL)
      case movie(URL, offset: Double)
    }
    let source: Source
    /// The wall-clock moment the frame shows.
    let time: Date
    /// From the file name, for the label when the stretch has two cameras.
    let camera: String?
  }

  // MARK: - The plan

  /// The frames of a stretch, in time order. A movie with no readable duration contributes no
  /// samples, only its still if it has one; a movie the folder doesn't name for OnCue's
  /// timestamp isn't a recording and is left out.
  static func plan(events: [ArmedStretch.Event], durations: [URL: Double]) -> [Frame] {
    var frames: [Frame] = []
    for event in events {
      let movies = event.files.filter { $0.pathExtension.lowercased() == "mov" }.sorted { $0.path < $1.path }
      for movie in movies {
        guard let start = FileOutputManager.recordingDate(fileName: movie.lastPathComponent) else { continue }
        let camera = cameraName(fileName: movie.lastPathComponent)
        let still = StillWriter.stillURL(for: movie)
        if event.files.contains(where: { $0.standardizedFileURL.path == still.standardizedFileURL.path }) {
          frames.append(Frame(source: .still(still), time: start, camera: camera))
        }
        if let duration = durations[movie], duration > 0 {
          var offset = 0.0
          while offset < duration {
            frames.append(Frame(source: .movie(movie, offset: offset), time: start.addingTimeInterval(offset), camera: camera))
            offset += step
          }
        }
      }
    }
    // Interleaved across cameras by the moment each frame shows; a still sorts before the
    // sample at the same moment, and a tie between cameras is broken by name so the order is fixed.
    return frames.enumerated().sorted { a, b in
      if a.element.time != b.element.time { return a.element.time < b.element.time }
      let aStill = { if case .still = a.element.source { return true }; return false }()
      let bStill = { if case .still = b.element.source { return true }; return false }()
      if aStill != bStill { return aStill }
      return a.offset < b.offset
    }.map { $0.element }
  }

  /// The camera in a name OnCue wrote: the first device after the timestamp, before any " + ".
  /// Nil for a name with no devices.
  static func cameraName(fileName: String) -> String? {
    let name = (fileName as NSString).deletingPathExtension
    guard let range = name.range(of: " - ") else { return nil }
    let devices = name[range.upperBound...]
    let first = devices.components(separatedBy: " + ").first ?? ""
    let trimmed = first.replacingOccurrences(of: " - [0-9]+s missing$", with: "", options: .regularExpression)
      .trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// Whether the frames come from more than one camera, which is when the label names them.
  static func hasTwoCameras(_ frames: [Frame]) -> Bool {
    return Set(frames.compactMap { $0.camera }).count > 1
  }

  // MARK: - Two cameras side by side (spec 0056)

  /// One moment on the shared timeline: what each camera shows, nil for a dark panel.
  struct PairedFrame: Equatable {
    let time: Date
    let left: Frame.Source?
    let right: Frame.Source?
  }

  struct Pairing: Equatable {
    let leftCamera: String
    let rightCamera: String
    let frames: [PairedFrame]
  }

  /// The two-camera plan, or nil unless the stretch's recordings name exactly two cameras.
  /// The timeline is every moment any recording has a frame for, on the two-second grid from
  /// the earliest start; at each, a camera shows the sample from the recording that covers it,
  /// its still at the first step at or after a recording's start, or nothing. `leftCamera` is
  /// the one Settings calls Camera; when it isn't in the stretch, the first by name goes left.
  static func pairedPlan(events: [ArmedStretch.Event], durations: [URL: Double], leftCamera: String?) -> Pairing? {
    struct Recording { let movie: URL; let start: Date; let duration: Double?; let still: URL?; let camera: String }
    var recordings: [Recording] = []
    for event in events {
      for movie in event.files where movie.pathExtension.lowercased() == "mov" {
        guard let start = FileOutputManager.recordingDate(fileName: movie.lastPathComponent),
          let camera = cameraName(fileName: movie.lastPathComponent) else { continue }
        let still = StillWriter.stillURL(for: movie)
        let hasStill = event.files.contains { $0.standardizedFileURL.path == still.standardizedFileURL.path }
        recordings.append(Recording(movie: movie, start: start, duration: durations[movie].flatMap { $0 > 0 ? $0 : nil },
                                    still: hasStill ? still : nil, camera: camera))
      }
    }
    let cameras = Array(Set(recordings.map { $0.camera })).sorted()
    guard cameras.count == 2 else { return nil }
    let left = leftCamera.flatMap { cameras.contains($0) ? $0 : nil } ?? cameras[0]
    let right = cameras.first { $0 != left }!

    guard let origin = recordings.map({ $0.start }).min() else { return nil }
    // A recording's still shows at the first grid step at or after its start.
    func stillStep(_ start: Date) -> Date {
      let since = start.timeIntervalSince(origin)
      return origin.addingTimeInterval((since / step).rounded(.up) * step)
    }
    var moments = Set<Date>()
    for recording in recordings {
      if recording.still != nil { moments.insert(stillStep(recording.start)) }
      if let duration = recording.duration {
        var t = stillStep(recording.start)
        while t < recording.start.addingTimeInterval(duration) {
          moments.insert(t)
          t = t.addingTimeInterval(step)
        }
      }
    }
    func source(for camera: String, at t: Date) -> Frame.Source? {
      let own = recordings.filter { $0.camera == camera }
      if let starting = own.first(where: { $0.still != nil && stillStep($0.start) == t }), let still = starting.still {
        return .still(still)
      }
      // The latest recording that covers the moment, in case pre-roll made two overlap.
      let covering = own.filter { r in
        guard let duration = r.duration else { return false }
        return r.start <= t && t < r.start.addingTimeInterval(duration)
      }.max { $0.start < $1.start }
      guard let recording = covering else { return nil }
      return .movie(recording.movie, offset: t.timeIntervalSince(recording.start))
    }
    let frames = moments.sorted().compactMap { t -> PairedFrame? in
      let l = source(for: left, at: t), r = source(for: right, at: t)
      guard l != nil || r != nil else { return nil }
      return PairedFrame(time: t, left: l, right: r)
    }
    return Pairing(leftCamera: left, rightCamera: right, frames: frames)
  }

  /// The two halves of the canvas, left then right.
  static func panelRects(canvas: CGSize) -> [CGRect] {
    let half = (canvas.width / 2).rounded(.down)
    return [CGRect(x: 0, y: 0, width: half, height: canvas.height),
            CGRect(x: half, y: 0, width: canvas.width - half, height: canvas.height)]
  }

  /// A two-panel frame: each picture letterboxed into its half, each half named at its top,
  /// the time once at the bottom-left of the whole. A dark half is a camera that wasn't
  /// recording at that moment.
  static func draw(panels: [(image: CGImage?, name: String)], time: String, into context: CGContext, canvas: CGSize) {
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(origin: .zero, size: canvas))
    let rects = panelRects(canvas: canvas)
    for (panel, rect) in zip(panels, rects) {
      if let image = panel.image {
        var fitted = letterbox(CGSize(width: image.width, height: image.height), in: rect.size)
        fitted.origin.x += rect.origin.x
        fitted.origin.y += rect.origin.y
        context.draw(image, in: fitted)
      }
      drawStrip(panel.name, into: context, canvas: canvas, at: CGPoint(x: rect.minX, y: rect.maxY), fromTop: true)
    }
    drawStrip(time, into: context, canvas: canvas, at: .zero, fromTop: false)
  }

  // MARK: - The file

  /// "What happened 2026-09-26 07.09 to 07.11.mov": starts with a word, so the window, the cost
  /// line and the stretch never take it for a recording. The same stretch gives the same name,
  /// so making it again replaces the last one.
  static func outputName(for stretch: ArmedStretch, calendar: Calendar = .current) -> String {
    let day = DateFormatter()
    day.calendar = calendar
    day.timeZone = calendar.timeZone
    day.locale = Locale(identifier: "en_US_POSIX")
    day.dateFormat = "yyyy-MM-dd HH.mm"
    let end = DateFormatter()
    end.calendar = calendar
    end.timeZone = calendar.timeZone
    end.locale = Locale(identifier: "en_US_POSIX")
    end.dateFormat = calendar.isDate(stretch.from, inSameDayAs: stretch.to) ? "HH.mm" : "yyyy-MM-dd HH.mm"
    return "What happened \(day.string(from: stretch.from)) to \(end.string(from: stretch.to)).mov"
  }

  // MARK: - Drawing

  /// Where an image of `size` sits inside `canvas`: fitted, never stretched, centred.
  static func letterbox(_ size: CGSize, in canvas: CGSize) -> CGRect {
    guard size.width > 0, size.height > 0, canvas.width > 0, canvas.height > 0 else { return .zero }
    let scale = min(canvas.width / size.width, canvas.height / size.height)
    let fitted = CGSize(width: (size.width * scale).rounded(.down), height: (size.height * scale).rounded(.down))
    return CGRect(x: ((canvas.width - fitted.width) / 2).rounded(.down),
                  y: ((canvas.height - fitted.height) / 2).rounded(.down),
                  width: fitted.width, height: fitted.height)
  }

  /// "14:12:04", or "14:12:04 · Hall" when the stretch has two cameras.
  static func label(for frame: Frame, twoCameras: Bool, calendar: Calendar = .current, locale: Locale = .current) -> String {
    let text = timeText(frame.time, calendar: calendar, locale: locale)
    guard twoCameras, let camera = frame.camera else { return text }
    return "\(text) · \(camera)"
  }

  /// One frame: black, the image letterboxed, the label in the bottom-left corner on a dark
  /// strip so it reads over any picture. Core Text, so no AppKit.
  static func draw(image: CGImage?, label: String, into context: CGContext, canvas: CGSize) {
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(origin: .zero, size: canvas))
    if let image = image {
      context.draw(image, in: letterbox(CGSize(width: image.width, height: image.height), in: canvas))
    }
    drawStrip(label, into: context, canvas: canvas, at: .zero, fromTop: false)
  }

  /// Text on a dark strip, anchored at `corner`: its bottom-left, or its top-left with `fromTop`.
  private static func drawStrip(_ text: String, into context: CGContext, canvas: CGSize, at corner: CGPoint, fromTop: Bool) {
    let fontSize = max(12, (canvas.height / 36).rounded())
    let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil) ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
    let attributes: [CFString: Any] = [
      kCTFontAttributeName: font,
      kCTForegroundColorAttributeName: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
    ]
    let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary))
    let bounds = CTLineGetBoundsWithOptions(line, [])
    let padding = (fontSize / 2).rounded()
    let height = bounds.height + padding * 2
    let origin = CGPoint(x: corner.x, y: fromTop ? corner.y - height : corner.y)
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.6))
    context.fill(CGRect(x: origin.x, y: origin.y, width: bounds.width + padding * 3, height: height))
    context.textPosition = CGPoint(x: origin.x + padding * 1.5, y: origin.y + padding - bounds.minY)
    CTLineDraw(line, context)
  }

  /// "14:12:04" in the user's locale, the time part of every label.
  static func timeText(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
    let time = DateFormatter()
    time.calendar = calendar
    time.timeZone = calendar.timeZone
    time.locale = locale
    time.dateFormat = DateFormatter.dateFormat(fromTemplate: "Hms", options: 0, locale: locale) ?? "HH:mm:ss"
    return time.string(from: date)
  }
}

/// Reads the stretch's files and writes the time-lapse, off the main queue (spec 0055).
enum TimeLapseRenderer {
  enum Failure: Error, Equatable {
    /// No still and no movie in the stretch could be read, so there was nothing to write.
    case nothingReadable
    case couldNotWrite(String)
  }

  /// Makes the movie for `events` in `folder`, replacing one with the same name, and calls
  /// `completion` on the main queue with where it landed.
  static func make(events: [ArmedStretch.Event], stretch: ArmedStretch, in folder: URL, leftCamera: String? = nil,
                   completion: @escaping (Result<URL, Failure>) -> Void) {
    Task.detached(priority: .utility) {
      let result = await render(events: events, stretch: stretch, in: folder, leftCamera: leftCamera)
      DispatchQueue.main.async { completion(result) }
    }
  }

  /// A frame ready to write: what to draw once the canvas is known, and whether anything was read.
  private struct Drawn {
    let hasImage: Bool
    let size: CGSize?
    let draw: (CGContext, CGSize) -> Void
  }

  static func render(events: [ArmedStretch.Event], stretch: ArmedStretch, in folder: URL,
                     leftCamera: String? = nil) async -> Result<URL, Failure> {
    // Durations first: a movie that won't load is left out of the plan rather than failing it.
    var durations: [URL: Double] = [:]
    var generators: [URL: AVAssetImageGenerator] = [:]
    for movie in Set(events.flatMap { $0.files }.filter { $0.pathExtension.lowercased() == "mov" }) {
      let asset = AVURLAsset(url: movie)
      guard let duration = try? await asset.load(.duration), duration.isNumeric, duration.seconds > 0 else { continue }
      durations[movie] = duration.seconds
      let generator = AVAssetImageGenerator(asset: asset)
      generator.appliesPreferredTrackTransform = true
      // Land on the keyframe at or after the moment (one a second, spec 0013) rather than
      // decoding up to the exact sample.
      generator.requestedTimeToleranceBefore = .zero
      generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
      generators[movie] = generator
    }
    func image(for source: TimeLapse.Frame.Source?) async -> CGImage? {
      switch source {
      case .still(let url)?:
        return CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
      case .movie(let url, let offset)?:
        return try? await generators[url]?.image(at: CMTime(seconds: offset, preferredTimescale: 600)).image
      case nil:
        return nil
      }
    }

    // Two cameras go side by side (spec 0056); one fills the frame (spec 0055).
    var drawn: [Drawn] = []
    if let pairing = TimeLapse.pairedPlan(events: events, durations: durations, leftCamera: leftCamera) {
      for frame in pairing.frames {
        let left = await image(for: frame.left), right = await image(for: frame.right)
        let first = left ?? right
        let time = TimeLapse.timeText(frame.time)
        drawn.append(Drawn(hasImage: first != nil, size: first.map { CGSize(width: $0.width, height: $0.height) }) { context, canvas in
          TimeLapse.draw(panels: [(left, pairing.leftCamera), (right, pairing.rightCamera)], time: time, into: context, canvas: canvas)
        })
      }
    } else {
      let frames = TimeLapse.plan(events: events, durations: durations)
      let twoCameras = TimeLapse.hasTwoCameras(frames)
      for frame in frames {
        let picture = await image(for: frame.source)
        let label = TimeLapse.label(for: frame, twoCameras: twoCameras)
        drawn.append(Drawn(hasImage: picture != nil, size: picture.map { CGSize(width: $0.width, height: $0.height) }) { context, canvas in
          TimeLapse.draw(image: picture, label: label, into: context, canvas: canvas)
        })
      }
    }

    let output = folder.appendingPathComponent(TimeLapse.outputName(for: stretch))
    let scratch = folder.appendingPathComponent(".\(UUID().uuidString).mov")
    var writer: AVAssetWriter?
    var input: AVAssetWriterInput?
    var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    var canvas = CGSize.zero
    var written = 0

    for frame in drawn {
      guard frame.hasImage, let size = frame.size else { continue }

      if writer == nil {
        canvas = size
        guard let started = openWriter(at: scratch, canvas: canvas) else {
          return .failure(.couldNotWrite("couldn't open a movie file in \(folder.lastPathComponent)"))
        }
        (writer, input, adaptor) = started
      }
      guard let adaptor = adaptor, let input = input, let pool = adaptor.pixelBufferPool else { continue }
      var buffer: CVPixelBuffer?
      guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let pixelBuffer = buffer else { continue }
      CVPixelBufferLockBaseAddress(pixelBuffer, [])
      if let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer), width: Int(canvas.width), height: Int(canvas.height),
                                 bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                 space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) {
        frame.draw(context, canvas)
      }
      CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
      while !input.isReadyForMoreMediaData {
        try? await Task.sleep(nanoseconds: 5_000_000)
      }
      let time = CMTime(value: CMTimeValue(written), timescale: TimeLapse.framesPerSecond)
      if adaptor.append(pixelBuffer, withPresentationTime: time) {
        written += 1
      }
    }

    guard let writer = writer, let input = input, written > 0 else {
      writer?.cancelWriting()
      try? FileManager.default.removeItem(at: scratch)
      return .failure(.nothingReadable)
    }
    input.markAsFinished()
    // The last frame gets its hold too: end the session a frame past it.
    writer.endSession(atSourceTime: CMTime(value: CMTimeValue(written), timescale: TimeLapse.framesPerSecond))
    await writer.finishWriting()
    guard writer.status == .completed else {
      try? FileManager.default.removeItem(at: scratch)
      return .failure(.couldNotWrite(writer.error?.localizedDescription ?? "the movie didn't finish"))
    }
    do {
      if FileManager.default.fileExists(atPath: output.path) {
        try FileManager.default.removeItem(at: output)
      }
      try FileManager.default.moveItem(at: scratch, to: output)
    } catch {
      try? FileManager.default.removeItem(at: scratch)
      return .failure(.couldNotWrite(error.localizedDescription))
    }
    FileOutputManager.makePrivate(output, permissions: 0o600)
    return .success(output)
  }

  /// Also the store preview's writer (spec 0061), at its own frame rate.
  static func openWriter(at url: URL, canvas: CGSize) -> (AVAssetWriter, AVAssetWriterInput, AVAssetWriterInputPixelBufferAdaptor)? {
    try? FileManager.default.removeItem(at: url)
    guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return nil }
    let settings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: Int(canvas.width),
      AVVideoHeightKey: Int(canvas.height),
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
      kCVPixelBufferWidthKey as String: Int(canvas.width),
      kCVPixelBufferHeightKey as String: Int(canvas.height),
    ])
    guard writer.canAdd(input) else { return nil }
    writer.add(input)
    guard writer.startWriting() else { return nil }
    writer.startSession(atSourceTime: .zero)
    return (writer, input, adaptor)
  }
}
