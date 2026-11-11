//
//  MotionDetector.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 4/10/20.
//  Copyright © 2020 Jake Van Alstyne
//

import Cocoa

class MotionDetector: NSObject {
  /// Fraction of sampled pixels in motion at which the level reads 100, the top of the motion meter and threshold slider.
  static let fullScaleFraction = 0.05

  /// Motion level on the 0 to 100 scale shared by the motion meter and the threshold slider. Can exceed 100.
  class func motionLevel(pixelsWithMotion: Int, pixelsTested: Int) -> Double {
    guard pixelsTested > 0 else {
      return 0
    }
    return Double(pixelsWithMotion) / Double(pixelsTested) / fullScaleFraction * 100
  }

  /// Each camera keeps its own motion threshold. One never set falls back to the last threshold
  /// set on any camera, so a newly added camera starts where the other one is.
  class func threshold(cameraID: String?, defaults: UserDefaults = .standard) -> Double {
    if let cameraID = cameraID, let value = defaults.object(forKey: thresholdKey(cameraID: cameraID)) as? Double {
      return value
    }
    return defaults.double(forKey: "motionTriggerThreshold")
  }

  class func setThreshold(_ value: Double, cameraID: String?, defaults: UserDefaults = .standard) {
    if let cameraID = cameraID {
      defaults.set(value, forKey: thresholdKey(cameraID: cameraID))
    }
    defaults.set(value, forKey: "motionTriggerThreshold")
  }

  class func thresholdKey(cameraID: String) -> String {
    return "motionTriggerThreshold.\(cameraID)"
  }

  class func detectMotion(pixelsWithMotion: Int,
                          pixelsTested: Int,
                          threshold: Double = UserDefaults.standard.double(forKey: "motionTriggerThreshold"),
                          enabled: Bool = UserDefaults.standard.bool(forKey: "motionTriggerEnabled")) -> Bool {
    return enabled && motionLevel(pixelsWithMotion: pixelsWithMotion, pixelsTested: pixelsTested) > threshold
  }
}
