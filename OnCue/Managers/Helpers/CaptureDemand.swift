//
//  CaptureDemand.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/20/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import Foundation

/// Why capture would be running at all (spec 0023). OnCue used to hold its cameras from launch to
/// quit, which made a lit camera indicator, a running session, and macOS 26.2's Edge Light mean
/// "OnCue is open" rather than "OnCue is watching". Capture now runs only while something needs it.
enum CaptureDemand {
  /// The arm state is the reason rather than a separate recording flag: `.recording` is one of its
  /// cases, so a recording in progress holds capture open by construction and the two can't
  /// disagree.
  static func shouldCapture(armState: RecordingManager.ArmState, popoverOpen: Bool, previewOpen: Bool) -> Bool {
    return armState != .unarmed || popoverOpen || previewOpen
  }

  /// Whether capture can stop now. It can't while a file is still being written: tearing the
  /// session down mid-write leaves a file with no index, which won't open.
  static func canStop(shouldCapture: Bool, writingFiles: Bool) -> Bool {
    return !shouldCapture && !writingFiles
  }
}
