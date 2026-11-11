//
//  MenuBarIcon.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/19/26.
//  Copyright © 2026 Jake Van Alstyne
//

import Cocoa

/// The menu bar icon: a lens (a ring and a center dot) drawn in the arm state's colors (spec 0014).
enum MenuBarIcon {
  enum Tint: Equatable {
    case gray, orange, red, blue, yellow
  }

  struct Appearance: Equatable {
    /// Monochrome, so macOS tints it to suit a light or dark menu bar.
    let isTemplate: Bool
    let ring: Tint
    let center: Tint
  }

  /// Orange while arming and red once armed match the popover's state text; armed also takes the
  /// app icon's blue center; recording is red throughout.
  ///
  /// A failed recording overrides all of it (spec 0027). Nothing else survives to be found later,
  /// and the menu bar is the only thing someone sees without opening anything, so it has to say
  /// that something is wrong even though only the popover can say what.
  static func appearance(for state: RecordingManager.ArmState, recordingFailed: Bool = false) -> Appearance {
    if recordingFailed {
      return Appearance(isTemplate: false, ring: .yellow, center: .yellow)
    }
    switch state {
    case .unarmed:
      return Appearance(isTemplate: true, ring: .gray, center: .gray)
    case .arming:
      return Appearance(isTemplate: false, ring: .orange, center: .gray)
    case .armed:
      return Appearance(isTemplate: false, ring: .red, center: .blue)
    case .recording:
      return Appearance(isTemplate: false, ring: .red, center: .red)
    }
  }

  static func image(for appearance: Appearance) -> NSImage {
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size, flipped: false) { rect in
      let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
      ring.lineWidth = 2.5
      color(appearance.ring, template: appearance.isTemplate).setStroke()
      ring.stroke()
      let center = NSBezierPath(ovalIn: rect.insetBy(dx: 6, dy: 6))
      color(appearance.center, template: appearance.isTemplate).setFill()
      center.fill()
      return true
    }
    image.isTemplate = appearance.isTemplate
    return image
  }

  private static func color(_ tint: Tint, template: Bool) -> NSColor {
    if template {
      return .black
    }
    switch tint {
    case .gray: return .systemGray
    case .orange: return .systemOrange
    case .red: return .systemRed
    case .blue: return .systemBlue
    case .yellow: return .systemYellow
    }
  }
}
