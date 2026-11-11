//
//  PreviewTitle.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/19/26.
//  Copyright © 2026 Jake Van Alstyne
//

import Foundation

enum PreviewTitle {
  /// "OnCue - [camera name]" while a camera is in use, "OnCue" while capture is audio only.
  static func title(cameraName: String?) -> String {
    return title(cameraNames: cameraName.map { [$0] } ?? [])
  }

  /// A window size that holds the cameras exactly, keeping the width where it is unless the screen
  /// is smaller. Without it the preview shows black bars above and below the cameras.
  static func contentSize(fitting aspect: CGSize, width: CGFloat, maximum: CGSize?) -> CGSize {
    var width = width
    if let maximum = maximum {
      width = min(width, maximum.width)
      let heightLimited = maximum.height * aspect.width / aspect.height
      width = min(width, heightLimited)
    }
    return CGSize(width: width, height: (width * aspect.height / aspect.width).rounded())
  }

  /// With two cameras, both names, joined as in recording file names: "OnCue - [first] + [second]".
  static func title(cameraNames: [String]) -> String {
    guard !cameraNames.isEmpty else {
      return "OnCue"
    }
    return "OnCue - \(cameraNames.joined(separator: " + "))"
  }
}
