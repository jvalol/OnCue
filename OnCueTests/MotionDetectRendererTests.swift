//
//  MotionDetectRendererTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/22/26.
//  Copyright © 2026 Jake Van Alstyne
//

import XCTest
import CoreMedia
import CoreVideo

/// The kernel on synthetic frames (spec 0040). The tests run in the app process, so the shader
/// library is the app's own. Uniform frames keep the Gaussian blur out of the arithmetic: away
/// from the edges a flat colour blurs to itself, and only the centre pixel is read.
class MotionDetectRendererTests: XCTestCase {
  private let width = 64, height = 64

  /// A BGRA frame of one colour, Metal-compatible so the renderer can wrap it in a texture.
  private func frame(r: UInt8, g: UInt8, b: UInt8) -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let attributes: [String: Any] = [kCVPixelBufferMetalCompatibilityKey as String: true,
                                     kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
    XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                       attributes as CFDictionary, &buffer), kCVReturnSuccess)
    let pixelBuffer = buffer!
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    let base = CVPixelBufferGetBaseAddress(pixelBuffer)!.assumingMemoryBound(to: UInt8.self)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    for y in 0..<height {
      for x in 0..<width {
        let i = y * bytesPerRow + x * 4
        base[i] = b; base[i + 1] = g; base[i + 2] = r; base[i + 3] = 255
      }
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    return pixelBuffer
  }

  private func centre(_ pixelBuffer: CVPixelBuffer) -> (r: UInt8, g: UInt8, b: UInt8) {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    let base = CVPixelBufferGetBaseAddress(pixelBuffer)!.assumingMemoryBound(to: UInt8.self)
    let i = (height / 2) * CVPixelBufferGetBytesPerRow(pixelBuffer) + (width / 2) * 4
    return (base[i + 2], base[i + 1], base[i])
  }

  private func render(last: CVPixelBuffer, current: CVPixelBuffer, preview: Bool = true) -> (mask: CVPixelBuffer, preview: CVPixelBuffer?) {
    let renderer = MotionDetectMetalRenderer()
    var description: CMFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: current, formatDescriptionOut: &description)
    renderer.prepare(with: description!, outputRetainedBufferCountHint: 3)
    XCTAssertTrue(renderer.isPrepared)
    let result = renderer.renderWithPreview(lastPixelBuffer: last, currentPixelBuffer: current, preview: preview)
    XCTAssertNotNil(result)
    return result!
  }

  private func assertClose(_ pixel: (r: UInt8, g: UInt8, b: UInt8), _ r: Int, _ g: Int, _ b: Int,
                           within tolerance: Int = 3, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertLessThanOrEqual(abs(Int(pixel.r) - r), tolerance, "\(message): red \(pixel.r) vs \(r)", file: file, line: line)
    XCTAssertLessThanOrEqual(abs(Int(pixel.g) - g), tolerance, "\(message): green \(pixel.g) vs \(g)", file: file, line: line)
    XCTAssertLessThanOrEqual(abs(Int(pixel.b) - b), tolerance, "\(message): blue \(pixel.b) vs \(b)", file: file, line: line)
  }

  /// No change: the mask shows the previous frame and the preview the current one, untouched.
  func testNothingChangedIsNotMarked() {
    let last = frame(r: 80, g: 120, b: 160), current = frame(r: 80, g: 120, b: 160)
    let (mask, preview) = render(last: last, current: current)
    assertClose(centre(mask), 80, 120, 160, "mask is the frame")
    assertClose(centre(preview!), 80, 120, 160, "preview is the frame")
  }

  /// A change under the cutoff (0.1 per channel: squared difference 0.03, cutoff 0.2) is not marked.
  func testASmallChangeIsUnderTheCutoff() {
    let last = frame(r: 100, g: 100, b: 100), current = frame(r: 126, g: 126, b: 126)
    let (mask, preview) = render(last: last, current: current)
    assertClose(centre(mask), 100, 100, 100, "mask is the previous frame")
    assertClose(centre(preview!), 126, 126, 126, "preview is the current frame")
  }

  /// Black to white: marked, and the mask's red is the 2019 expression, 1.5 × 3 clamped to 1.
  /// The preview is the white frame blended 0.8 toward red: (1, 0.2, 0.2).
  func testAFullChangeIsMarkedRedInTheMaskAndTintedInThePreview() {
    let last = frame(r: 0, g: 0, b: 0), current = frame(r: 255, g: 255, b: 255)
    let (mask, preview) = render(last: last, current: current)
    assertClose(centre(mask), 255, 0, 0, "mask: pure red, green and blue zero for the sampler")
    assertClose(centre(preview!), 255, 51, 51, "preview: 0.8 of the way from white to red")
  }

  /// With nothing showing the preview (spec 0041), the kernel writes only the mask, and the mask
  /// is the same one the two-output variant writes.
  func testWithoutAPreviewOnlyTheMaskIsWrittenAndItIsTheSameMask() {
    let last = frame(r: 0, g: 0, b: 0), current = frame(r: 255, g: 255, b: 255)
    let (mask, preview) = render(last: last, current: current, preview: false)
    XCTAssertNil(preview)
    assertClose(centre(mask), 255, 0, 0, "mask-only variant marks the same red")
    let (maskWithPreview, _) = render(last: frame(r: 100, g: 100, b: 100), current: frame(r: 126, g: 126, b: 126), preview: true)
    let (maskWithout, none) = render(last: frame(r: 100, g: 100, b: 100), current: frame(r: 126, g: 126, b: 126), preview: false)
    XCTAssertNil(none)
    let a = centre(maskWithPreview), b = centre(maskWithout)
    XCTAssertEqual(a.r, b.r); XCTAssertEqual(a.g, b.g); XCTAssertEqual(a.b, b.b)
  }

  /// Just over the cutoff (0.5 per channel: squared 0.75): marked, red 1.5 × 0.75 clamped to 1.
  /// The sampler reads green and blue exactly zero and red above zero.
  func testAChangeOverTheCutoffIsMarkedWithZeroGreenAndBlue() {
    let last = frame(r: 0, g: 0, b: 0), current = frame(r: 128, g: 128, b: 128)
    let (mask, preview) = render(last: last, current: current)
    let m = centre(mask)
    XCTAssertGreaterThan(m.r, 0)
    XCTAssertEqual(m.g, 0)
    XCTAssertEqual(m.b, 0)
    assertClose(centre(preview!), 230, 26, 26, "preview: grey 128 blended 0.8 toward red")
  }
}
