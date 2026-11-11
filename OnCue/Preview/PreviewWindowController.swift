//
//  PreviewWindowController.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 11/13/19.
//  Copyright © 2019 Jake Van Alstyne. All rights reserved.
//

import Cocoa

class PreviewWindowController: NSWindowController {
  override func windowDidLoad() {
    super.windowDidLoad()

    self.window?.level = .floating
  }
}

extension PreviewWindowController {
  static func freshController() -> PreviewWindowController {
    let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
    let identifier = NSStoryboard.SceneIdentifier("PreviewWindowController")
    guard let previewWindowController = storyboard.instantiateController(withIdentifier: identifier) as? PreviewWindowController else {
      fatalError("Why cant I find PreviewWindowController? - Check Main.storyboard")
    }
    return previewWindowController
  }
}
