//
//  AudioDetector.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/19/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import Cocoa

class AudioDetector: NSObject {
  /// Average power, in dBFS, at or below which the level reads 0. 0 dBFS reads 100.
  static let floorDecibels = -60.0

  /// Sound level on the 0 to 100 scale shared by the sound meter and the audio trigger slider, linear in dB.
  class func level(decibels: Double) -> Double {
    // Silence can come through as -infinity; anything not a number reads as silence.
    guard decibels.isFinite else {
      return 0
    }
    let clamped = min(max(decibels, floorDecibels), 0)
    return (clamped - floorDecibels) / -floorDecibels * 100
  }

  class func detectSound(level: Double, threshold: Double, enabled: Bool) -> Bool {
    return enabled && level > threshold
  }
}
