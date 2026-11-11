//
//  StoreScreenshots.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 10/2/26.
//  Copyright © 2026 Jake Van Alstyne
//

#if DEBUG
import Cocoa
import AVFoundation

/// The App Store's pictures, drawn by the app itself (spec 0057). A Debug build launched with
/// `-renderStoreScreenshots <folder>` puts the popover and Settings into each state worth a
/// picture, with set meter levels and a made-up stretch, writes each as a PNG on the store's
/// canvas, and quits. No camera, no screen capture, the same picture every time.
///
/// Everything the views read from defaults comes from the volatile argument domain, so nothing
/// here touches the user's settings.
enum StoreScreenshots {
  static let argumentKey = "renderStoreScreenshots"
  /// The store's largest Mac canvas.
  static let canvas = NSSize(width: 2880, height: 1800)

  static var folder: URL? {
    guard let path = UserDefaults.standard.string(forKey: argumentKey), !path.isEmpty else { return nil }
    return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
  }

  /// Before anything reads defaults: the settings the pictures show, overriding the user's
  /// without writing them. A schedule that always contains now, both triggers on, and a stretch
  /// that ended ten minutes ago.
  static func prepareDefaults() {
    // Either render mode; the key the launch argument used is carried into the overrides, since
    // setting the argument domain replaces what the command line put there.
    let key = folder != nil ? argumentKey : StorePreview.argumentKey
    guard let folder = folder ?? StorePreview.folder else { return }
    let now = Date()
    // Every day, two windows that between them always contain now, so "on schedule" always applies.
    let schedule = Schedule(windows: [ScheduleWindow(days: Set(1...7), start: 6 * 60, end: 22 * 60),
                                      ScheduleWindow(days: Set(1...7), start: 22 * 60, end: 6 * 60)])
    var overrides: [String: Any] = [
      key: folder.path,
      DetectLaunch.keyforLaunch: false,
      "motionTriggerEnabled": true,
      "audioTriggerEnabled": true,
      "motionTriggerThreshold": 50.0,
      "audioTriggerThreshold": 70.0,
      "timeoutValueInSeconds": 5,
      "preRollSeconds": 5,
      "recordingsLimitGB": 20,
      "armAtLogin": false,
      "openPreviewWindowAtLaunch": false,
      Schedule.enabledKey: true,
      UpdateNotice.lastRunKey: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
      UpdateNotice.pendingKey: "",
      ArmedStretch.fromKey: now.addingTimeInterval(-(2 * 3600 + 35 * 60)),
      ArmedStretch.toKey: now.addingTimeInterval(-10 * 60),
    ]
    if let data = try? JSONEncoder().encode(schedule) {
      overrides[Schedule.windowsKey] = data
    }
    // Settings shows the second camera chosen when the Mac has one to choose.
    if let second = secondCameraOnThisMac() {
      overrides["secondCameraID"] = second.uniqueID
    }
    UserDefaults.standard.setVolatileDomain(overrides, forName: UserDefaults.argumentDomain)
  }

  /// A camera that isn't the built-in one, for the two-camera pictures.
  private static func secondCameraOnThisMac() -> AVCaptureDevice? {
    let cameras = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external],
                                                   mediaType: .video, position: .unspecified).devices
    return cameras.first { $0.deviceType == .external } ?? (cameras.count > 1 ? cameras[1] : nil)
  }

  /// Draws every picture into the folder. Synchronous, before the run loop turns, so nothing
  /// the capture manager does asynchronously can move the state underneath it.
  static func render(into folder: URL) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let manager = AppDelegate.recordingManager
    manager.useRecordingsFolderForScreenshot(try fakeRecordings())

    let popover = PopoverViewController.freshController()
    let host = NSWindow(contentRect: NSRect(origin: .zero, size: popover.view.fittingSize),
                        styleMask: [.borderless], backing: .buffered, defer: false)
    host.appearance = NSAppearance(named: .darkAqua)
    host.contentViewController = popover
    popover.devicesChanged(cameraName: "FaceTime HD Camera", secondCameraName: nil, microphoneName: "MacBook Pro Microphone")

    let second = secondCameraOnThisMac()?.localizedName ?? "HD Pro Webcam C920"
    let pictures: [(name: String, state: RecordingManager.ArmState, countdown: Int, lid: Bool, motion: Double, sound: Double, second: Double?)] = [
      ("1-popover-unarmed", .unarmed, 0, false, 8, 22, nil),
      ("2-popover-arming", .arming, 3, true, 12, 30, nil),
      ("3-popover-armed", .armed, 0, false, 18, 35, nil),
      ("4-popover-two-cameras", .armed, 0, false, 14, 28, 46),
      ("5-popover-recording", .recording, 0, false, 82, 61, nil),
    ]
    for picture in pictures {
      popover.devicesChanged(cameraName: "FaceTime HD Camera", secondCameraName: picture.second == nil ? nil : second,
                             microphoneName: "MacBook Pro Microphone")
      manager.setStateForScreenshot(picture.state, countdown: picture.countdown, bySchedule: picture.state == .armed)
      AppDelegate.sleepRiskMonitor.overrideForScreenshot(lidWouldStopWatching: picture.lid)
      popover.setMetersForScreenshot(motion: picture.motion, sound: picture.sound, second: picture.second)
      popover.refreshForScreenshot()
      popover.view.layoutSubtreeIfNeeded()
      host.setContentSize(popover.view.fittingSize)
      popover.view.layoutSubtreeIfNeeded()
      let image = try bitmap(of: popover.view)
      try write(compose(image, roundedWithArrow: true), to: folder.appendingPathComponent("\(picture.name)-\(Int(canvas.width))x\(Int(canvas.height)).png"))
    }
    popover.devicesChanged(cameraName: "FaceTime HD Camera", secondCameraName: nil, microphoneName: "MacBook Pro Microphone")

    let settings = SettingsWindowController.freshController()
    if let window = settings.window, let frame = window.contentView?.superview {
      window.appearance = NSAppearance(named: .darkAqua)
      window.contentViewController?.view.layoutSubtreeIfNeeded()
      window.layoutIfNeeded()
      let image = try bitmap(of: frame)
      try write(compose(image, roundedWithArrow: false), to: folder.appendingPathComponent("6-settings-\(Int(canvas.width))x\(Int(canvas.height)).png"))
    }

    try write(compose(iconStrip(), roundedWithArrow: false, at: 4), to: folder.appendingPathComponent("7-menubar-\(Int(canvas.width))x\(Int(canvas.height)).png"))
    try? FileManager.default.removeItem(at: manager.recordingsFolder)
  }

  // MARK: - Pieces

  /// Twelve events across the stretch, for the line under the state, in a folder of its own.
  static func fakeRecordings() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("OnCue-store-screenshots-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    guard let from = UserDefaults.standard.object(forKey: ArmedStretch.fromKey) as? Date,
      let to = UserDefaults.standard.object(forKey: ArmedStretch.toKey) as? Date else { return folder }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
    for i in 0..<12 {
      let moment = from.addingTimeInterval((to.timeIntervalSince(from) / 13) * Double(i + 1))
      let base = "\(formatter.string(from: moment)) - FaceTime HD Camera + MacBook Pro Microphone"
      // Thirty seconds of movie at the encoder's rate, and a still, so the cost line reads true.
      FileManager.default.createFile(atPath: folder.appendingPathComponent("\(base).mov").path, contents: Data(count: 30_000_000))
      FileManager.default.createFile(atPath: folder.appendingPathComponent("\(base).jpg").path, contents: Data(count: 300_000))
    }
    return folder
  }

  static func bitmap(of view: NSView) throws -> NSImage {
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
      throw NSError(domain: "StoreScreenshots", code: 1, userInfo: [NSLocalizedDescriptionKey: "no bitmap for \(view)"])
    }
    view.cacheDisplay(in: view.bounds, to: rep)
    let image = NSImage(size: view.bounds.size)
    image.addRepresentation(rep)
    return image
  }

  /// The five states of the menu bar icon in a row, each named.
  private static func iconStrip() -> NSImage {
    let states: [(label: String, appearance: MenuBarIcon.Appearance)] = [
      ("Unarmed", MenuBarIcon.appearance(for: .unarmed)),
      ("Arming", MenuBarIcon.appearance(for: .arming)),
      ("Armed", MenuBarIcon.appearance(for: .armed)),
      ("Recording", MenuBarIcon.appearance(for: .recording)),
      ("Recording failed", MenuBarIcon.appearance(for: .armed, recordingFailed: true)),
    ]
    let cell = NSSize(width: 150, height: 64)
    let size = NSSize(width: cell.width * CGFloat(states.count), height: cell.height)
    return NSImage(size: size, flipped: false) { _ in
      for (index, state) in states.enumerated() {
        let origin = CGFloat(index) * cell.width
        var icon = MenuBarIcon.image(for: state.appearance)
        if state.appearance.isTemplate {
          // A template icon draws in the menu bar's text colour; here that's white.
          icon = icon.tinted(.white)
        }
        icon.draw(in: NSRect(x: origin + (cell.width - 22) / 2, y: 32, width: 22, height: 22))
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white]
        let text = NSAttributedString(string: state.label, attributes: attributes)
        let width = text.size().width
        text.draw(at: NSPoint(x: origin + (cell.width - width) / 2, y: 12))
      }
      return true
    }
  }

  /// The canvas behind every picture: the site's blue running into its teal, so the store's
  /// pictures and the site are one thing. The first cut was a near-black field with the popover at
  /// 2x in the middle, a third of the width, which on the store page read as a black rectangle
  /// (2026-10-12). The colours are the site's button blue and its logo teal.
  static let canvasTop = NSColor(red: 0x00 / 255.0, green: 0xBC / 255.0, blue: 0xF9 / 255.0, alpha: 1)
  static let canvasBottom = NSColor(red: 0x4a / 255.0, green: 0xa8 / 255.0, blue: 0x9f / 255.0, alpha: 1)
  /// How much of the canvas a picture may fill, each way.
  static let fill: CGFloat = 0.9

  /// The largest whole scale, up to `scale`, at which the picture stays inside `fill` of the
  /// canvas. Whole scales keep text crisp; the popover lands at 4x, Settings at 2x.
  static func scale(for size: NSSize, arrow: CGFloat, upTo most: CGFloat = 4, in canvas: NSSize = StoreScreenshots.canvas) -> CGFloat {
    var chosen: CGFloat = 1
    for candidate in stride(from: CGFloat(1), through: most, by: 1) {
      if size.width * candidate <= canvas.width * fill && (size.height + arrow) * candidate <= canvas.height * fill {
        chosen = candidate
      }
    }
    return chosen
  }

  /// The picture scaled to fill most of the canvas, centred, with a shadow; the popover gets its
  /// rounded corners and arrow, since the view alone is a plain rectangle. The preview (0061)
  /// composes onto its own canvas with a caption along the bottom, through the same code, so the
  /// pictures and the clip can't drift apart.
  static func compose(_ image: NSImage, roundedWithArrow: Bool, at fixed: CGFloat? = nil,
                      onto canvas: NSSize = StoreScreenshots.canvas, caption: String? = nil) -> NSImage {
    let scale = fixed ?? StoreScreenshots.scale(for: image.size, arrow: roundedWithArrow ? 12 : 0, in: canvas)
    let drawn = NSSize(width: image.size.width * scale, height: image.size.height * scale)
    let arrow: CGFloat = roundedWithArrow ? 12 * scale : 0
    // A caption takes the bottom of the canvas; the picture centres in what's left.
    let captionBand: CGFloat = caption == nil ? 0 : canvas.height * 0.14
    let origin = NSPoint(x: ((canvas.width - drawn.width) / 2).rounded(),
                         y: (captionBand + (canvas.height - captionBand - drawn.height - arrow) / 2).rounded())
    return NSImage(size: canvas, flipped: false) { _ in
      NSGradient(starting: canvasTop, ending: canvasBottom)?.draw(in: NSRect(origin: .zero, size: canvas), angle: -60)
      let rect = NSRect(origin: origin, size: drawn)
      let shadow = NSShadow()
      shadow.shadowColor = NSColor(white: 0, alpha: 0.45)
      shadow.shadowBlurRadius = 24 * scale
      shadow.shadowOffset = NSSize(width: 0, height: -8 * scale)
      if roundedWithArrow {
        let path = NSBezierPath(roundedRect: rect, xRadius: 10 * scale, yRadius: 10 * scale)
        let tip = NSPoint(x: rect.midX, y: rect.maxY + arrow)
        path.move(to: NSPoint(x: tip.x - arrow, y: rect.maxY - 1))
        path.line(to: tip)
        path.line(to: NSPoint(x: tip.x + arrow, y: rect.maxY - 1))
        path.close()
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor(white: 0.13, alpha: 1).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 10 * scale, yRadius: 10 * scale).addClip()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        NSGraphicsContext.restoreGraphicsState()
      } else {
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor(white: 0.13, alpha: 1).setFill()
        rect.fill()
        NSGraphicsContext.restoreGraphicsState()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
      }
      if let caption = caption, !caption.isEmpty {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let textShadow = NSShadow()
        textShadow.shadowColor = NSColor(white: 0, alpha: 0.5)
        textShadow.shadowBlurRadius = canvas.height / 90
        textShadow.shadowOffset = NSSize(width: 0, height: -canvas.height / 360)
        let text = NSAttributedString(string: caption, attributes: [
          .font: NSFont.systemFont(ofSize: canvas.height / 24, weight: .semibold),
          .foregroundColor: NSColor.white, .paragraphStyle: style, .shadow: textShadow])
        let band = NSRect(x: canvas.width * 0.08, y: 0, width: canvas.width * 0.84, height: captionBand)
        let height = text.boundingRect(with: NSSize(width: band.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin]).height
        text.draw(with: NSRect(x: band.minX, y: band.midY - height / 2, width: band.width, height: height), options: [.usesLineFragmentOrigin])
      }
      return true
    }
  }

  private static func write(_ image: NSImage, to url: URL) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width), pixelsHigh: Int(canvas.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = canvas
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(origin: .zero, size: canvas))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else {
      throw NSError(domain: "StoreScreenshots", code: 2, userInfo: [NSLocalizedDescriptionKey: "no PNG for \(url.lastPathComponent)"])
    }
    try png.write(to: url)
  }
}

private extension NSImage {
  func tinted(_ color: NSColor) -> NSImage {
    let image = NSImage(size: size, flipped: false) { rect in
      self.draw(in: rect)
      color.set()
      rect.fill(using: .sourceAtop)
      return true
    }
    return image
  }
}
#endif
