//
//  DetectionZones.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/22/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import Foundation

/// Where in the picture motion counts (spec 0042): rectangles in normalised picture coordinates,
/// 0 to 1 on each axis with the origin at the top left, so they survive a resolution change. One
/// list per camera, keyed the way thresholds are. No rectangles means the whole picture counts,
/// which is what every camera starts with.
struct DetectionZones: Equatable, Codable {
  var rects: [CGRect] = []

  var isEmpty: Bool { rects.isEmpty }

  static func key(cameraID: String) -> String {
    return "detectionZones.\(cameraID)"
  }

  // MARK: - Membership

  /// Whether the pixel at (x, y) in a picture of the given size is inside any zone. With no zones,
  /// every pixel is.
  func contains(x: Int, y: Int, width: Int, height: Int) -> Bool {
    guard !rects.isEmpty, width > 0, height > 0 else { return true }
    let point = CGPoint(x: (CGFloat(x) + 0.5) / CGFloat(width), y: (CGFloat(y) + 0.5) / CGFloat(height))
    return rects.contains { $0.contains(point) }
  }

  /// The sampler's count, with the zones as the universe: every `stride`th pixel on each axis is
  /// tested only if it's inside a zone, and `marked` says whether it moved. Pure, so the tests
  /// run it against synthetic masks.
  func count(width: Int, height: Int, stride step: Int, marked: (Int, Int) -> Bool) -> (tested: Int, withMotion: Int) {
    var tested = 0, withMotion = 0
    for y in stride(from: 0, to: height - 1, by: step) {
      for x in stride(from: 0, to: width - 1, by: step) {
        guard contains(x: x, y: y, width: width, height: height) else { continue }
        tested += 1
        if marked(x, y) { withMotion += 1 }
      }
    }
    return (tested, withMotion)
  }

  // MARK: - Storage

  static func load(cameraID: String?, defaults: UserDefaults = .standard) -> DetectionZones {
    guard let cameraID = cameraID, let data = defaults.data(forKey: key(cameraID: cameraID)),
      let zones = try? JSONDecoder().decode(DetectionZones.self, from: data) else {
      return DetectionZones()
    }
    return zones
  }

  func save(cameraID: String, defaults: UserDefaults = .standard) {
    if let data = try? JSONEncoder().encode(self) {
      defaults.set(data, forKey: DetectionZones.key(cameraID: cameraID))
    }
    DetectionZones.remember(self, cameraID: cameraID)
  }

  // MARK: - What the pipeline reads

  /// The sampler asks thirty times a second from its own queue, so the answer comes from a cache
  /// the editor updates on save, not from defaults each frame.
  private static var cache: [String: DetectionZones] = [:]
  private static let lock = NSLock()

  static func current(cameraID: String?, defaults: UserDefaults = .standard) -> DetectionZones {
    guard let cameraID = cameraID else { return DetectionZones() }
    lock.lock()
    if let cached = cache[cameraID] {
      lock.unlock()
      return cached
    }
    lock.unlock()
    let loaded = load(cameraID: cameraID, defaults: defaults)
    remember(loaded, cameraID: cameraID)
    return loaded
  }

  private static func remember(_ zones: DetectionZones, cameraID: String) {
    lock.lock()
    cache[cameraID] = zones
    lock.unlock()
  }
}
