//
//  ZoneEditorView.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/22/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import Cocoa

/// The layer over a camera's preview where zones are drawn and edited (spec 0042). Drag on the
/// picture to draw one, click to select, drag a selected one to move it, Delete to remove it,
/// Escape to deselect. While any exist, the picture outside them is dimmed, so what is ignored
/// reads as ignored, and the motion painted there still shows through: seen, not counted.
///
/// Zones are kept in normalised picture coordinates with the origin at the top left; the view's
/// own coordinates have the origin at the bottom left and the picture aspect-fitted into the
/// bounds, so every mouse point goes through `pictureRect` and a flip.
class ZoneEditorView: NSView {
  /// The camera whose zones these are. nil until capture has named it; edits are ignored until then.
  var cameraID: String? {
    didSet {
      zones = DetectionZones.load(cameraID: cameraID)
      selected = nil
      needsDisplay = true
      layoutControls()
    }
  }
  /// The rectangle the picture occupies in this view, set by whoever knows the picture's size.
  var pictureRect: CGRect = .zero {
    didSet { if pictureRect != oldValue { needsDisplay = true; layoutControls() } }
  }

  private var zones = DetectionZones()
  private var selected: Int?
  private enum Drag { case none, drawing(from: CGPoint, to: CGPoint), moving(index: Int, last: CGPoint) }
  private var drag = Drag.none

  private let hint = NSTextField(wrappingLabelWithString: String(localized: "Drag to draw a zone. With none drawn, the whole frame is used.", comment: "Preview window hint"))
  private let clearButton = NSButton(title: String(localized: "Clear zones", comment: "Preview window button"), target: nil, action: nil)
  /// Smaller than this on either side, in picture fractions, is a click, not a zone.
  private let minimumZone: CGFloat = 0.02

  override init(frame: CGRect) {
    super.init(frame: frame)
    hint.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    hint.textColor = .white
    hint.alignment = .center
    hint.drawsBackground = true
    hint.backgroundColor = NSColor.black.withAlphaComponent(0.5)
    hint.translatesAutoresizingMaskIntoConstraints = true
    addSubview(hint)
    clearButton.bezelStyle = .rounded
    clearButton.controlSize = .small
    clearButton.target = self
    clearButton.action = #selector(clearZones(_:))
    clearButton.translatesAutoresizingMaskIntoConstraints = true
    addSubview(clearButton)
    layoutControls()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var acceptsFirstResponder: Bool { true }
  override var isFlipped: Bool { false }

  override func layout() {
    super.layout()
    layoutControls()
  }

  private func layoutControls() {
    let inset: CGFloat = 8
    hint.isHidden = !zones.isEmpty || pictureRect.isEmpty
    clearButton.isHidden = zones.isEmpty || pictureRect.isEmpty
    // Wrapped to the picture's width: with two cameras each preview is half the window.
    let maxWidth = max(pictureRect.width - 2 * inset - 12, 40)
    hint.preferredMaxLayoutWidth = maxWidth
    let fitted = hint.sizeThatFits(NSSize(width: maxWidth, height: .greatestFiniteMagnitude))
    hint.frame = CGRect(x: pictureRect.midX - fitted.width / 2 - 6, y: pictureRect.minY + inset,
                        width: fitted.width + 12, height: fitted.height + 4)
    clearButton.sizeToFit()
    clearButton.frame.origin = CGPoint(x: pictureRect.maxX - clearButton.frame.width - inset,
                                       y: pictureRect.maxY - clearButton.frame.height - inset)
  }

  // MARK: - Coordinates

  /// Normalised picture point (origin top left) for a view point, or nil outside the picture.
  private func normalised(_ point: CGPoint) -> CGPoint? {
    guard !pictureRect.isEmpty, pictureRect.contains(point) else { return nil }
    return CGPoint(x: (point.x - pictureRect.minX) / pictureRect.width,
                   y: 1 - (point.y - pictureRect.minY) / pictureRect.height)
  }

  /// The view rectangle for a normalised zone.
  private func viewRect(_ zone: CGRect) -> CGRect {
    return CGRect(x: pictureRect.minX + zone.minX * pictureRect.width,
                  y: pictureRect.minY + (1 - zone.maxY) * pictureRect.height,
                  width: zone.width * pictureRect.width,
                  height: zone.height * pictureRect.height)
  }

  private func clampedToPicture(_ zone: CGRect) -> CGRect {
    var r = zone
    r.origin.x = min(max(r.origin.x, 0), 1 - r.width)
    r.origin.y = min(max(r.origin.y, 0), 1 - r.height)
    return r
  }

  // MARK: - Drawing

  override func draw(_ dirtyRect: NSRect) {
    guard !pictureRect.isEmpty else { return }
    if !zones.isEmpty {
      let dim = NSBezierPath(rect: pictureRect)
      for zone in zones.rects { dim.append(NSBezierPath(rect: viewRect(zone))) }
      dim.windingRule = .evenOdd
      NSColor.black.withAlphaComponent(0.45).setFill()
      dim.fill()
      for (index, zone) in zones.rects.enumerated() {
        let outline = NSBezierPath(rect: viewRect(zone).insetBy(dx: 1, dy: 1))
        outline.lineWidth = 2
        (index == selected ? NSColor.systemYellow : NSColor.white).setStroke()
        outline.stroke()
      }
    }
    if case let .drawing(from, to) = drag {
      let band = NSBezierPath(rect: CGRect(x: min(from.x, to.x), y: min(from.y, to.y),
                                           width: abs(to.x - from.x), height: abs(to.y - from.y)))
      band.lineWidth = 1
      band.setLineDash([4, 3], count: 2, phase: 0)
      NSColor.white.setStroke()
      band.stroke()
    }
  }

  // MARK: - Editing

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    let point = convert(event.locationInWindow, from: nil)
    guard cameraID != nil, let inPicture = normalised(point) else { return }
    if let hit = zones.rects.lastIndex(where: { $0.contains(inPicture) }) {
      selected = hit
      drag = .moving(index: hit, last: inPicture)
    } else {
      selected = nil
      drag = .drawing(from: point, to: point)
    }
    needsDisplay = true
  }

  override func mouseDragged(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    switch drag {
    case let .drawing(from, _):
      drag = .drawing(from: from, to: CGPoint(x: min(max(point.x, pictureRect.minX), pictureRect.maxX),
                                              y: min(max(point.y, pictureRect.minY), pictureRect.maxY)))
    case let .moving(index, last):
      guard let now = normalised(point) ?? clampedNormalised(point) else { return }
      var zone = zones.rects[index]
      zone.origin.x += now.x - last.x
      zone.origin.y += now.y - last.y
      zones.rects[index] = clampedToPicture(zone)
      drag = .moving(index: index, last: now)
    case .none:
      return
    }
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    switch drag {
    case let .drawing(from, to):
      if let a = normalised(from), let b = normalised(to) {
        let zone = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        if zone.width >= minimumZone && zone.height >= minimumZone {
          zones.rects.append(zone)
          selected = zones.rects.count - 1
          save()
        }
      }
    case .moving:
      save()
    case .none:
      break
    }
    drag = .none
    needsDisplay = true
  }

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 51, 117:  // Delete, forward delete
      if let index = selected, zones.rects.indices.contains(index) {
        zones.rects.remove(at: index)
        selected = nil
        save()
        needsDisplay = true
      }
    case 53:  // Escape
      selected = nil
      needsDisplay = true
    default:
      super.keyDown(with: event)
    }
  }

  @objc private func clearZones(_ sender: Any?) {
    zones = DetectionZones()
    selected = nil
    save()
    needsDisplay = true
  }

  /// A point dragged outside the picture, brought back to its edge, so a move can't be lost.
  private func clampedNormalised(_ point: CGPoint) -> CGPoint? {
    guard !pictureRect.isEmpty else { return nil }
    let clamped = CGPoint(x: min(max(point.x, pictureRect.minX), pictureRect.maxX),
                          y: min(max(point.y, pictureRect.minY), pictureRect.maxY))
    return normalised(clamped)
  }

  private func save() {
    guard let cameraID = cameraID else { return }
    zones.save(cameraID: cameraID)
    layoutControls()
  }
}
