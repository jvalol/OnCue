//
//  StorePreviewStoryboard.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 11/9/26.
//  Copyright © 2026 Jake Van Alstyne
//

import Foundation

/// What the App Store preview shows, second by second (spec 0061): a list of scenes, each a
/// popover state held for a few seconds with the meters moving between two levels and one caption
/// under it. A value, so a test can add it up; the drawing is `StorePreview`'s.
enum StorePreviewStoryboard {
  static let framesPerSecond = 30
  /// Apple's bounds for a preview.
  static let shortestSeconds = 15.0
  static let longestSeconds = 30.0

  struct Scene: Equatable {
    let state: RecordingManager.ArmState
    let countdown: Int
    let bySchedule: Bool
    /// Where the motion and sound meters start and end over the scene, 0 to 100.
    let motion: (from: Double, to: Double)
    let sound: (from: Double, to: Double)
    /// Which line of captions.txt sits under it; consecutive scenes may share one.
    let caption: Int
    let seconds: Double

    static func == (a: Scene, b: Scene) -> Bool {
      a.state == b.state && a.countdown == b.countdown && a.bySchedule == b.bySchedule
        && a.motion == b.motion && a.sound == b.sound && a.caption == b.caption && a.seconds == b.seconds
    }
  }

  /// About 24 seconds in six captions (open question 1). The arm and the meters come first,
  /// since previews autoplay in search results and the first seconds are all most viewers give;
  /// the stretch line comes last, for the viewer who stays. The countdown is three one-second
  /// scenes so the number visibly changes.
  static let scenes: [Scene] = [
    Scene(state: .unarmed, countdown: 0, bySchedule: false, motion: (6, 10), sound: (14, 18), caption: 0, seconds: 4),
    Scene(state: .arming, countdown: 3, bySchedule: false, motion: (10, 10), sound: (18, 20), caption: 1, seconds: 1),
    Scene(state: .arming, countdown: 2, bySchedule: false, motion: (10, 12), sound: (20, 20), caption: 1, seconds: 1),
    Scene(state: .arming, countdown: 1, bySchedule: false, motion: (12, 10), sound: (20, 22), caption: 1, seconds: 1),
    Scene(state: .armed, countdown: 0, bySchedule: false, motion: (10, 38), sound: (22, 44), caption: 2, seconds: 5),
    Scene(state: .recording, countdown: 0, bySchedule: false, motion: (72, 84), sound: (58, 66), caption: 3, seconds: 5),
    // Unarmed again, where the popover carries the stretch line ("Armed for 2h 25m: 12
    // recordings between…"), which is what this caption is about.
    Scene(state: .unarmed, countdown: 0, bySchedule: false, motion: (16, 12), sound: (24, 20), caption: 4, seconds: 4),
    Scene(state: .armed, countdown: 0, bySchedule: true, motion: (8, 6), sound: (16, 14), caption: 5, seconds: 3),
  ]

  static var totalSeconds: Double { scenes.reduce(0) { $0 + $1.seconds } }
  static var frameCount: Int { Int((totalSeconds * Double(framesPerSecond)).rounded()) }
  static var captionCount: Int { (scenes.map(\.caption).max() ?? -1) + 1 }

  /// The scene a frame falls in and how far through it, 0 to 1.
  static func scene(atFrame frame: Int) -> (index: Int, progress: Double)? {
    var start = 0.0
    let second = Double(frame) / Double(framesPerSecond)
    for (index, scene) in scenes.enumerated() {
      if second < start + scene.seconds {
        return (index, (second - start) / scene.seconds)
      }
      start += scene.seconds
    }
    return nil
  }

  /// A meter level for a frame: eased between the scene's ends, with a small wobble so a held
  /// level still looks alive.
  static func level(_ range: (from: Double, to: Double), progress: Double, wobble phase: Double) -> Double {
    let eased = progress < 0.5 ? 2 * progress * progress : 1 - pow(-2 * progress + 2, 2) / 2
    let value = range.from + (range.to - range.from) * eased + 2.5 * sin(phase * 7)
    return min(100, max(0, value))
  }
}
