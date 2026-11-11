//
//  TimeLapseTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/30/26.
//  Copyright © 2026 Jake Van Alstyne
//

import XCTest
import AVFoundation
import CoreVideo

class TimeLapseTests: XCTestCase {
  private var folder: URL!
  private let noon = Date(timeIntervalSince1970: 1_790_000_000)

  private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
  }

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("TimeLapseTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: folder)
  }

  private func url(_ name: String) -> URL { folder.appendingPathComponent(name) }

  /// A 32BGRA frame of one colour, the capture format.
  private func frame(width: Int = 64, height: Int = 48, blue: UInt8 = 200, green: UInt8 = 30, red: UInt8 = 10) -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    XCTAssertEqual(CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
    let pixelBuffer = buffer!
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    let base = CVPixelBufferGetBaseAddress(pixelBuffer)!.assumingMemoryBound(to: UInt8.self)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    for y in 0..<height {
      for x in 0..<width {
        let p = base + y * bytesPerRow + x * 4
        p[0] = blue; p[1] = green; p[2] = red; p[3] = 255
      }
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    return pixelBuffer
  }

  // MARK: - Names

  func testTheCameraIsTheFirstDeviceInTheName() {
    XCTAssertEqual(TimeLapse.cameraName(fileName: "2026-09-26 07.09.12 - Hall Camera + MacBook Pro Microphone.mov"), "Hall Camera")
    XCTAssertEqual(TimeLapse.cameraName(fileName: "2026-09-26 07.09.12 - Hall Camera.jpg"), "Hall Camera")
    XCTAssertEqual(TimeLapse.cameraName(fileName: "2026-09-26 07.09.12 - Hall Camera - 28s missing.mov"), "Hall Camera")
    XCTAssertNil(TimeLapse.cameraName(fileName: "2026-09-26 07.09.12.mov"))
  }

  func testTheOutputNameIsNotARecordingToTheWindow() {
    let stretch = ArmedStretch(from: noon, to: noon.addingTimeInterval(2 * 3600))
    let name = TimeLapse.outputName(for: stretch, calendar: utc)
    XCTAssertTrue(name.hasPrefix("What happened "), name)
    XCTAssertTrue(name.hasSuffix(".mov"), name)
    XCTAssertNil(FileOutputManager.recordingDate(fileName: name))
    XCTAssertEqual(TimeLapse.outputName(for: stretch, calendar: utc), name, "the same stretch names the same file")
  }

  func testAStretchAcrossMidnightNamesBothDays() {
    // The fixed instant is 14:13 UTC, so eight hours on is 22:13 and eleven is 01:13 the next day.
    let stretch = ArmedStretch(from: noon.addingTimeInterval(8 * 3600), to: noon.addingTimeInterval(11 * 3600))
    let name = TimeLapse.outputName(for: stretch, calendar: utc)
    XCTAssertEqual(name, "What happened 2026-09-21 22.13 to 2026-09-22 01.13.mov")
  }

  // MARK: - The plan

  private func event(_ files: [String], at secondsAfterNoon: TimeInterval = 0) -> ArmedStretch.Event {
    ArmedStretch.Event(started: noon.addingTimeInterval(secondsAfterNoon), files: files.map(url))
  }

  func testTheStillComesFirstThenAFrameEveryTwoSeconds() {
    let movie = url("2026-09-21 14.13.20 - Hall.mov")
    let frames = TimeLapse.plan(events: [event(["2026-09-21 14.13.20 - Hall.mov", "2026-09-21 14.13.20 - Hall.jpg"])],
                                durations: [movie: 7])
    XCTAssertEqual(frames.map { $0.source }, [.still(url("2026-09-21 14.13.20 - Hall.jpg")),
                                              .movie(movie, offset: 0), .movie(movie, offset: 2),
                                              .movie(movie, offset: 4), .movie(movie, offset: 6)])
    XCTAssertEqual(frames.map { $0.camera }, Array(repeating: "Hall", count: 5))
    XCTAssertEqual(frames.last?.time.timeIntervalSince(frames.first!.time), 6)
  }

  func testAMovieWithoutADurationContributesOnlyItsStill() {
    let frames = TimeLapse.plan(events: [event(["2026-09-21 14.13.20 - Hall.mov", "2026-09-21 14.13.20 - Hall.jpg"])],
                                durations: [:])
    XCTAssertEqual(frames.map { $0.source }, [.still(url("2026-09-21 14.13.20 - Hall.jpg"))])
  }

  func testTwoCamerasInterleaveByTime() {
    let hall = url("2026-09-21 14.13.20 - Hall.mov"), kitchen = url("2026-09-21 14.13.21 - Kitchen.mov")
    let frames = TimeLapse.plan(events: [event(["2026-09-21 14.13.20 - Hall.mov", "2026-09-21 14.13.21 - Kitchen.mov"])],
                                durations: [hall: 3, kitchen: 3])
    XCTAssertEqual(frames.map { $0.source }, [.movie(hall, offset: 0), .movie(kitchen, offset: 0),
                                              .movie(hall, offset: 2), .movie(kitchen, offset: 2)])
    XCTAssertTrue(TimeLapse.hasTwoCameras(frames))
  }

  func testAFileThatIsNotARecordingIsLeftOut() {
    let frames = TimeLapse.plan(events: [event(["What happened 2026-09-21 14.00 to 15.00.mov", "notes.mov"])],
                                durations: [url("notes.mov"): 10])
    XCTAssertTrue(frames.isEmpty)
  }

  // MARK: - Two cameras side by side (spec 0056)

  private func twoCameraEvent() -> (event: ArmedStretch.Event, hall: URL, kitchen: URL) {
    let hall = url("2026-09-21 14.13.20 - Hall.mov"), kitchen = url("2026-09-21 14.13.21 - Kitchen.mov")
    let event = ArmedStretch.Event(started: noon, files: [hall, StillWriter.stillURL(for: hall), kitchen, StillWriter.stillURL(for: kitchen)])
    return (event, hall, kitchen)
  }

  func testTwoCamerasShareOneTimelineWithStillsAtTheirFirstStep() {
    let (event, hall, kitchen) = twoCameraEvent()
    let pairing = TimeLapse.pairedPlan(events: [event], durations: [hall: 7, kitchen: 5], leftCamera: nil)!
    XCTAssertEqual(pairing.leftCamera, "Hall")
    XCTAssertEqual(pairing.rightCamera, "Kitchen")
    // Steps at 20, 22, 24, 26 from the earliest start (the name's time, in local time). Hall
    // covers 20..<27, Kitchen 21..<26.
    let origin = FileOutputManager.recordingDate(fileName: hall.lastPathComponent)!
    XCTAssertEqual(pairing.frames.map { $0.time.timeIntervalSince(origin) }, [0, 2, 4, 6])
    XCTAssertEqual(pairing.frames.map { $0.left }, [.still(StillWriter.stillURL(for: hall)), .movie(hall, offset: 2),
                                                   .movie(hall, offset: 4), .movie(hall, offset: 6)])
    // Kitchen starts at 21: dark at 20, its still at 22, a sample at 24, over by 26.
    XCTAssertEqual(pairing.frames.map { $0.right }, [nil, .still(StillWriter.stillURL(for: kitchen)),
                                                    .movie(kitchen, offset: 3), nil])
  }

  func testTheSettingsCameraGoesLeftWhenItIsInTheStretch() {
    let (event, hall, kitchen) = twoCameraEvent()
    let pairing = TimeLapse.pairedPlan(events: [event], durations: [hall: 7, kitchen: 5], leftCamera: "Kitchen")!
    XCTAssertEqual(pairing.leftCamera, "Kitchen")
    XCTAssertEqual(pairing.frames.first?.left, nil)
    XCTAssertEqual(pairing.frames.first?.right, .still(StillWriter.stillURL(for: hall)))
    let elsewhere = TimeLapse.pairedPlan(events: [event], durations: [hall: 7, kitchen: 5], leftCamera: "Garage")!
    XCTAssertEqual(elsewhere.leftCamera, "Hall", "a camera not in the stretch doesn't pick the side")
  }

  func testOneCameraHasNoPairs() {
    let movie = url("2026-09-21 14.13.20 - Hall.mov")
    let event = ArmedStretch.Event(started: noon, files: [movie, StillWriter.stillURL(for: movie)])
    XCTAssertNil(TimeLapse.pairedPlan(events: [event], durations: [movie: 7], leftCamera: nil))
    XCTAssertNil(TimeLapse.pairedPlan(events: [], durations: [:], leftCamera: nil))
  }

  func testAMomentNeitherCameraHasIsNotAFrame() {
    let hall = url("2026-09-21 14.13.20 - Hall.mov"), kitchen = url("2026-09-21 14.14.20 - Kitchen.mov")
    let event = ArmedStretch.Event(started: noon, files: [hall, kitchen])
    let pairing = TimeLapse.pairedPlan(events: [event], durations: [hall: 3, kitchen: 3], leftCamera: nil)!
    // Hall at 0 and 2; Kitchen a minute later at 60 and 62; nothing in between.
    let origin = FileOutputManager.recordingDate(fileName: hall.lastPathComponent)!
    XCTAssertEqual(pairing.frames.map { $0.time.timeIntervalSince(origin) }, [0, 2, 60, 62])
    XCTAssertEqual(pairing.frames.map { $0.right != nil }, [false, false, true, true])
  }

  func testThePanelsSplitTheCanvasEvenly() {
    XCTAssertEqual(TimeLapse.panelRects(canvas: CGSize(width: 1920, height: 1080)),
                   [CGRect(x: 0, y: 0, width: 960, height: 1080), CGRect(x: 960, y: 0, width: 960, height: 1080)])
    // A 16:9 picture in a 960 by 1080 half: full width, letterboxed.
    XCTAssertEqual(TimeLapse.letterbox(CGSize(width: 1920, height: 1080), in: CGSize(width: 960, height: 1080)),
                   CGRect(x: 0, y: 270, width: 960, height: 540))
  }

  func testTwoCamerasRenderAtTheFirstFramesSize() async throws {
    let stretch = ArmedStretch(from: noon, to: noon.addingTimeInterval(600))
    let (event, hall, kitchen) = twoCameraEvent()
    XCTAssertTrue(StillWriter.write(frame(width: 64, height: 48), besideMovie: hall))
    XCTAssertTrue(StillWriter.write(frame(width: 32, height: 32, blue: 20, green: 200), besideMovie: kitchen))
    // No movies on disk: the stills alone, each at its own step, so two frames.
    let result = await TimeLapseRenderer.render(events: [event], stretch: stretch, in: folder, leftCamera: "Hall")
    let output = try XCTUnwrap(try? result.get())
    let seconds = try await duration(of: output)
    XCTAssertEqual(seconds, 0.5, accuracy: 0.01)
    let tracks = try await AVURLAsset(url: output).loadTracks(withMediaType: .video)
    let size = try await XCTUnwrap(tracks.first).load(.naturalSize)
    XCTAssertEqual(size, CGSize(width: 64, height: 48))
  }

  func testDrawingTwoPanelsDoesNotThrow() {
    let canvas = CGSize(width: 320, height: 240)
    let context = CGContext(data: nil, width: 320, height: 240, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
    TimeLapse.draw(panels: [(nil, "Hall"), (nil, "Kitchen")], time: "14:13:24", into: context, canvas: canvas)
  }

  // MARK: - Drawing

  func testLetterboxingFitsWithoutStretching() {
    XCTAssertEqual(TimeLapse.letterbox(CGSize(width: 1920, height: 1080), in: CGSize(width: 1920, height: 1080)),
                   CGRect(x: 0, y: 0, width: 1920, height: 1080))
    // A 4:3 picture in a 16:9 canvas: full height, pillarboxed.
    XCTAssertEqual(TimeLapse.letterbox(CGSize(width: 640, height: 480), in: CGSize(width: 1920, height: 1080)),
                   CGRect(x: 240, y: 0, width: 1440, height: 1080))
    // A 16:9 picture in a 4:3 canvas: full width, letterboxed.
    XCTAssertEqual(TimeLapse.letterbox(CGSize(width: 1920, height: 1080), in: CGSize(width: 640, height: 480)),
                   CGRect(x: 0, y: 60, width: 640, height: 360))
  }

  func testTheLabelNamesTheCameraOnlyWithTwo() {
    let frame = TimeLapse.Frame(source: .still(url("a.jpg")), time: noon.addingTimeInterval(4), camera: "Hall")
    let one = TimeLapse.label(for: frame, twoCameras: false, calendar: utc, locale: Locale(identifier: "en_US_POSIX"))
    XCTAssertEqual(one, "14:13:24")
    let two = TimeLapse.label(for: frame, twoCameras: true, calendar: utc, locale: Locale(identifier: "en_US_POSIX"))
    XCTAssertEqual(two, "14:13:24 · Hall")
  }

  func testDrawingAnyCanvasDoesNotThrow() {
    for canvas in [CGSize(width: 16, height: 16), CGSize(width: 320, height: 240), CGSize(width: 1920, height: 1080)] {
      let context = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
      TimeLapse.draw(image: nil, label: "14:13:24 · Hall", into: context, canvas: canvas)
    }
  }

  // MARK: - Rendering

  private func duration(of movie: URL) async throws -> Double {
    try await AVURLAsset(url: movie).load(.duration).seconds
  }

  func testStillsBecomeAMovieOfAQuarterSecondEach() async throws {
    let stretch = ArmedStretch(from: noon, to: noon.addingTimeInterval(600))
    var files: [URL] = []
    for i in 0..<3 {
      let movie = url("2026-09-21 14.13.2\(i) - Hall.mov")
      XCTAssertTrue(StillWriter.write(frame(blue: UInt8(60 * i)), besideMovie: movie))
      files.append(StillWriter.stillURL(for: movie))
      files.append(movie)  // named, never written: unreadable, so it contributes no samples
    }
    let result = await TimeLapseRenderer.render(events: [ArmedStretch.Event(started: noon, files: files)], stretch: stretch, in: folder)
    let output = try XCTUnwrap(try? result.get())
    XCTAssertEqual(output.lastPathComponent, TimeLapse.outputName(for: stretch))
    let seconds = try await duration(of: output)
    XCTAssertEqual(seconds, 0.75, accuracy: 0.01)
    let tracks = try await AVURLAsset(url: output).loadTracks(withMediaType: .video)
    let size = try await XCTUnwrap(tracks.first).load(.naturalSize)
    XCTAssertEqual(size, CGSize(width: 64, height: 48))
  }

  func testAMovieIsSampledEveryTwoSeconds() async throws {
    // Make a movie first, the way the renderer does, then use it as a recording.
    let source = ArmedStretch(from: noon, to: noon.addingTimeInterval(600))
    // Twenty recordings a second apart, each with a still and no movie on disk: twenty frames.
    var files: [URL] = []
    for i in 0..<20 {
      let movie = url(String(format: "2026-09-21 14.13.%02d - Hall.mov", i))
      XCTAssertTrue(StillWriter.write(frame(), besideMovie: movie))
      files.append(StillWriter.stillURL(for: movie))
      files.append(movie)
    }
    let first = await TimeLapseRenderer.render(events: [ArmedStretch.Event(started: noon, files: files)],
                                               stretch: source, in: folder)
    let made = try XCTUnwrap(try? first.get())
    // Twenty frames at four a second is a five-second movie; renamed as a recording it samples at 0, 2 and 4.
    let recording = url("2026-09-22 09.00.00 - Hall.mov")
    try FileManager.default.moveItem(at: made, to: recording)
    let recorded = try await duration(of: recording)
    XCTAssertEqual(recorded, 5, accuracy: 0.01)
    let stretch = ArmedStretch(from: noon.addingTimeInterval(86_400), to: noon.addingTimeInterval(90_000))
    let result = await TimeLapseRenderer.render(events: [ArmedStretch.Event(started: recording.creationOrNow, files: [recording])],
                                                stretch: stretch, in: folder)
    let output = try XCTUnwrap(try? result.get())
    let sampled = try await duration(of: output)
    XCTAssertEqual(sampled, 0.75, accuracy: 0.01)
  }

  func testNothingReadableWritesNothing() async {
    let stretch = ArmedStretch(from: noon, to: noon.addingTimeInterval(600))
    let result = await TimeLapseRenderer.render(events: [ArmedStretch.Event(started: noon, files: [url("2026-09-21 14.13.20 - Hall.mov")])],
                                                stretch: stretch, in: folder)
    XCTAssertEqual(result, .failure(.nothingReadable))
    XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(TimeLapse.outputName(for: stretch)).path))
  }

  func testMakingItAgainReplacesTheLastOne() async throws {
    let stretch = ArmedStretch(from: noon, to: noon.addingTimeInterval(600))
    let movie = url("2026-09-21 14.13.20 - Hall.mov")
    XCTAssertTrue(StillWriter.write(frame(), besideMovie: movie))
    let files = [StillWriter.stillURL(for: movie), movie]
    _ = await TimeLapseRenderer.render(events: [ArmedStretch.Event(started: noon, files: files)], stretch: stretch, in: folder)
    _ = await TimeLapseRenderer.render(events: [ArmedStretch.Event(started: noon, files: files)], stretch: stretch, in: folder)
    let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("What happened") }
    XCTAssertEqual(names.count, 1)
  }
}

private extension URL {
  var creationOrNow: Date { (try? resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date() }
}
