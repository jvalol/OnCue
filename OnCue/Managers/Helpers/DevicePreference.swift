//
//  DevicePreference.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/19/26.
//  Copyright © 2026 Jake Van Alstyne
//

import Foundation

/// Which device to use, given the one the user chose (saved by unique ID) and what's connected.
enum DevicePreference {
  /// Saved instead of a device's ID to mean "none, on purpose", as against no choice yet, which is
  /// nil and falls back to whatever is there. Settings uses the same empty string for its "no
  /// camera" entry, and for the mic's system-default and the second camera's none.
  static let noDevice = ""

  /// The chosen device if it's connected, otherwise `fallback`, otherwise the first available.
  /// The choice itself is never cleared here, so the chosen device is used again once it's back.
  /// `noDevice` means no device at all, and nothing falls back into its place.
  static func preferred<Device>(savedID: String?, available: [Device], fallback: Device? = nil, id: (Device) -> String) -> Device? {
    if savedID == noDevice {
      return nil
    }
    if let savedID = savedID, let chosen = available.first(where: { id($0) == savedID }) {
      return chosen
    }
    return fallback ?? available.first
  }

  /// The second camera: the one chosen for it, if it's connected and isn't already the first camera.
  /// There's no fallback; with none chosen, or the chosen one missing, there's no second camera.
  /// A single camera is always the first one, so with no first camera there is no second either.
  static func second<Device>(savedID: String?, available: [Device], firstID: String?, id: (Device) -> String) -> Device? {
    guard let firstID = firstID, let savedID = savedID, savedID != firstID else {
      return nil
    }
    return available.first { id($0) == savedID }
  }

  /// The cameras that can be offered as a second camera: every connected one except the first, and
  /// none at all when there's no first camera. Settings builds its list from this and picks the
  /// selection with `second`, both against the camera actually in use, so the two pickers can
  /// never name the same camera.
  static func secondChoices<Device>(available: [Device], firstID: String?, id: (Device) -> String) -> [Device] {
    guard let firstID = firstID else {
      return []
    }
    return available.filter { id($0) != firstID }
  }

  /// Which pipelines record when a trigger fires: every running one with a camera or a mic.
  /// With two cameras that's both; a pipeline left without a camera isn't running.
  static func recordingPipelines(_ pipelines: [(running: Bool, hasCamera: Bool, hasMicrophone: Bool)]) -> [Int] {
    return pipelines.indices.filter {
      pipelines[$0].running && (pipelines[$0].hasCamera || pipelines[$0].hasMicrophone)
    }
  }

  /// What a trigger's setting becomes after a device choice. Choosing none turns it off: a
  /// trigger left on for a device you deliberately removed records an intention you just
  /// contradicted. A device going missing on its own doesn't come through here, so its trigger is
  /// left alone and resumes when the device comes back (spec 0028).
  static func triggerEnabled(wasEnabled: Bool, choosingNone: Bool) -> Bool {
    return wasEnabled && !choosingNone
  }

  /// Whether a device that just connected should replace the one in use: when there's none in use,
  /// or when it's the chosen one and capture is on a fallback. Any other device leaves things alone.
  /// Having chosen `noDevice`, nothing connecting changes that; the empty slot was asked for.
  static func shouldSwitch(toConnectedID connectedID: String, currentID: String?, savedID: String?) -> Bool {
    if savedID == noDevice {
      return false
    }
    guard let currentID = currentID else {
      return true
    }
    return connectedID == savedID && currentID != savedID
  }
}
