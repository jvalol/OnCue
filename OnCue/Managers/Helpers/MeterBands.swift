//
//  MeterBands.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/20/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import Foundation

/// Where a meter turns yellow and red (spec 0025). The colours used to switch at a fixed 75 and
/// 90, which had nothing to do with the slider underneath: a meter could sit red while the
/// threshold was far above it, or stay green while a recording was about to start. The only
/// question a meter answers is whether what it's picking up is enough to trigger, so the colours
/// follow the threshold instead.
enum MeterBands {
  /// Yellow covers the top quarter below the threshold, so it scales with the setting rather than
  /// vanishing when the threshold is low.
  static let warningShare = 0.75

  /// `warning` and `critical` for an `NSLevelIndicator` measuring against `threshold`.
  ///
  /// The extremes are left honest rather than special-cased. Both detectors compare with a strict
  /// `>`, so a threshold at the top means nothing can trigger and the meter stays green, and a
  /// threshold of zero means anything triggers and it's red throughout.
  static func edges(threshold: Double) -> (warning: Double, critical: Double) {
    let critical = max(0, threshold)
    return (warning: critical * warningShare, critical: critical)
  }
}
