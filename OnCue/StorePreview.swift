//
//  StorePreview.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 11/9/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

#if DEBUG
import Cocoa
import AVFoundation

/// The App Store's preview clip, drawn by the app itself (spec 0061), the way the pictures are
/// (0057). A Debug build launched with `-renderStorePreview <folder>` walks the storyboard,
/// snapshots the popover each frame onto the same canvas the pictures use with a caption along
/// the bottom, writes an H.264 movie, and quits. Captions come from `captions.txt` in the folder.
enum StorePreview {
  static let argumentKey = "renderStorePreview"
  static let canvas = NSSize(width: 1920, height: 1080)
  static let fileName = "oncue-preview-1920x1080.mov"
  static let captionsName = "captions.txt"

  static var folder: URL? {
    guard let path = UserDefaults.standard.string(forKey: argumentKey), !path.isEmpty else { return nil }
    return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
  }

  static func render(into folder: URL) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let captions = try readCaptions(in: folder)
    let manager = AppDelegate.recordingManager
    manager.useRecordingsFolderForScreenshot(try StoreScreenshots.fakeRecordings())
    defer { try? FileManager.default.removeItem(at: manager.recordingsFolder) }

    let popover = PopoverViewController.freshController()
    let host = NSWindow(contentRect: NSRect(origin: .zero, size: popover.view.fittingSize),
                        styleMask: [.borderless], backing: .buffered, defer: false)
    host.appearance = NSAppearance(named: .darkAqua)
    host.contentViewController = popover
    popover.devicesChanged(cameraName: "FaceTime HD Camera", secondCameraName: nil, microphoneName: "MacBook Pro Microphone")
    AppDelegate.sleepRiskMonitor.overrideForScreenshot(lidWouldStopWatching: false)

    let output = folder.appendingPathComponent(fileName)
    guard let (writer, input, adaptor) = TimeLapseRenderer.openWriter(at: output, canvas: canvas) else {
      throw NSError(domain: "StorePreview", code: 1, userInfo: [NSLocalizedDescriptionKey: "couldn't open \(fileName)"])
    }
    let fps = Int32(StorePreviewStoryboard.framesPerSecond)
    var shown = -1
    for frame in 0..<StorePreviewStoryboard.frameCount {
      guard let (index, progress) = StorePreviewStoryboard.scene(atFrame: frame) else { break }
      let scene = StorePreviewStoryboard.scenes[index]
      if index != shown {
        manager.setStateForScreenshot(scene.state, countdown: scene.countdown, bySchedule: scene.bySchedule)
        shown = index
      }
      let phase = Double(frame) / Double(fps)
      popover.setMetersForScreenshot(motion: StorePreviewStoryboard.level(scene.motion, progress: progress, wobble: phase),
                                     sound: StorePreviewStoryboard.level(scene.sound, progress: progress, wobble: phase + 1.3))
      popover.refreshForScreenshot()
      popover.view.layoutSubtreeIfNeeded()
      host.setContentSize(popover.view.fittingSize)
      popover.view.layoutSubtreeIfNeeded()
      let picture = try StoreScreenshots.bitmap(of: popover.view)
      let caption = scene.caption < captions.count ? captions[scene.caption] : ""
      let composed = StoreScreenshots.compose(picture, roundedWithArrow: true, onto: canvas, caption: caption)
      try append(composed, at: frame, to: adaptor, input: input)
    }
    input.markAsFinished()
    writer.endSession(atSourceTime: CMTime(value: CMTimeValue(StorePreviewStoryboard.frameCount), timescale: fps))
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    guard writer.status == .completed else {
      throw NSError(domain: "StorePreview", code: 2, userInfo: [NSLocalizedDescriptionKey: writer.error?.localizedDescription ?? "the movie didn't finish"])
    }
  }

  /// One line per caption index, in order. The file is Jake's copy; the marker rule applies to it.
  private static func readCaptions(in folder: URL) throws -> [String] {
    let url = folder.appendingPathComponent(captionsName)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
      throw NSError(domain: "StorePreview", code: 3, userInfo: [NSLocalizedDescriptionKey: "no \(captionsName) in \(folder.path)"])
    }
    return text.split(separator: "\n", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }

  private static func append(_ image: NSImage, at frame: Int, to adaptor: AVAssetWriterInputPixelBufferAdaptor,
                             input: AVAssetWriterInput) throws {
    guard let pool = adaptor.pixelBufferPool else { throw NSError(domain: "StorePreview", code: 4, userInfo: [NSLocalizedDescriptionKey: "no pixel buffer pool"]) }
    var buffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let pixelBuffer = buffer else {
      throw NSError(domain: "StorePreview", code: 5, userInfo: [NSLocalizedDescriptionKey: "no pixel buffer"])
    }
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    if let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer), width: Int(canvas.width), height: Int(canvas.height),
                               bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) {
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
      image.draw(in: NSRect(origin: .zero, size: canvas))
      NSGraphicsContext.restoreGraphicsState()
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
    let time = CMTime(value: CMTimeValue(frame), timescale: Int32(StorePreviewStoryboard.framesPerSecond))
    guard adaptor.append(pixelBuffer, withPresentationTime: time) else {
      throw NSError(domain: "StorePreview", code: 6, userInfo: [NSLocalizedDescriptionKey: "frame \(frame) wasn't accepted"])
    }
  }
}
#endif
