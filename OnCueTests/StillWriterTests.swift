//
//  StillWriterTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/25/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import XCTest
import CoreVideo
import ImageIO

class StillWriterTests: XCTestCase {
  private var folder: URL!

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("StillWriterTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: folder)
  }

  /// A 32BGRA frame, the capture format, filled with one colour.
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

  func testTheStillTakesTheMoviesNameWithAJPEGExtension() {
    let movie = URL(fileURLWithPath: "/tmp/OnCue/2026-09-25 17.40.12 - FaceTime HD Camera + MacBook Pro Microphone.mov")
    XCTAssertEqual(StillWriter.stillURL(for: movie).path,
                   "/tmp/OnCue/2026-09-25 17.40.12 - FaceTime HD Camera + MacBook Pro Microphone.jpg")
  }

  func testANumberedMovieKeepsItsNumberOnTheStill() {
    let movie = URL(fileURLWithPath: "/tmp/OnCue/2026-09-25 17.40.12 2.mov")
    XCTAssertEqual(StillWriter.stillURL(for: movie).lastPathComponent, "2026-09-25 17.40.12 2.jpg")
  }

  func testTheFrameComesBackAsAJPEGOfTheSameSize() throws {
    let data = try XCTUnwrap(StillWriter.jpegData(from: frame(width: 64, height: 48)))
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.jpeg")
    let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 64)
    XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 48)
  }

  func testTheStillLandsBesideTheMovieAndIsPrivate() throws {
    let movie = folder.appendingPathComponent("2026-09-25 17.40.12.mov")
    XCTAssertTrue(StillWriter.write(frame(), besideMovie: movie))
    let still = folder.appendingPathComponent("2026-09-25 17.40.12.jpg")
    XCTAssertTrue(FileManager.default.fileExists(atPath: still.path))
    let permissions = try FileManager.default.attributesOfItem(atPath: still.path)[.posixPermissions] as? Int
    XCTAssertEqual(permissions, 0o600)
  }

  func testTheStillCarriesTheFramesColour() throws {
    // Mostly blue in BGRA, so a JPEG that came back red would mean the channels were read wrong.
    let data = try XCTUnwrap(StillWriter.jpegData(from: frame(blue: 220, green: 20, red: 20)))
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    let pixel = try XCTUnwrap(context.data?.assumingMemoryBound(to: UInt8.self))
    XCTAssertLessThan(pixel[0], 80, "red")
    XCTAssertGreaterThan(pixel[2], 160, "blue")
  }

  func testRemovingTheStillLeavesEverythingElse() throws {
    let movie = folder.appendingPathComponent("2026-09-25 17.40.12.mov")
    try Data("movie".utf8).write(to: movie)
    StillWriter.write(frame(), besideMovie: movie)
    StillWriter.removeStill(besideMovie: movie)
    XCTAssertFalse(FileManager.default.fileExists(atPath: StillWriter.stillURL(for: movie).path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: movie.path))
  }

  /// A recorder whose file never starts (nothing was ever appended) leaves no still behind, even
  /// though it had a frame in hand.
  func testARecordingThatNeverStartsLeavesNoStill() {
    let recorder = PreRollRecorder()
    let movie = folder.appendingPathComponent("2026-09-25 17.40.12.mov")
    recorder.noteFrame(frame())
    let finished = expectation(description: "finished")
    recorder.startRecording(to: movie) { _, error in
      XCTAssertNotNil(error)
      finished.fulfill()
    }
    recorder.stopRecording()
    wait(for: [finished], timeout: 5)
    XCTAssertFalse(FileManager.default.fileExists(atPath: StillWriter.stillURL(for: movie).path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: movie.path))
  }
}
