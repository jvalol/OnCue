//
//  EdgeLight.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/20/26.
//  Copyright © 2026 Jake Van Alstyne
//

import AVFoundation

/// macOS 26.2's Edge Light lights the screen's edges to illuminate whoever is in front of the
/// camera. It engages whenever an app holds a supported camera, which means it engages for OnCue,
/// lighting the room OnCue is watching and changing the scene it records (spec 0022).
///
/// OnCue can't turn it off: the properties are read-only, there's no control mode as Center Stage
/// has, and no Info.plist opt-out as Studio Light has. All it can do is say so.
enum EdgeLight {
  /// Whether the edge light is on screen right now. False on anything before macOS 26.2, which
  /// has never heard of it.
  static var isActive: Bool {
    if #available(macOS 26.2, *) {
      return AVCaptureDevice.isEdgeLightActive
    }
    return false
  }

  /// Whether to say something about it. Only with a camera: without one there's nothing for Edge
  /// Light to attach to, and nothing OnCue is doing that could have turned it on.
  static func shouldWarn(active: Bool, hasCamera: Bool) -> Bool {
    return active && hasCamera
  }
}
