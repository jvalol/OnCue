//
//  AboutWindowController.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 4/11/20.
//  Copyright © 2020 Jake Van Alstyne
//

import Cocoa

class AboutWindowController: NSWindowController {
    override func windowDidLoad() {
      super.windowDidLoad()
    }
  }

  extension AboutWindowController {
    static func freshController() -> AboutWindowController {
      let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
      let identifier = NSStoryboard.SceneIdentifier("AboutWindowController")
      guard let aboutWindowController = storyboard.instantiateController(withIdentifier: identifier) as? AboutWindowController else {
        fatalError("Why cant I find AboutWindowController? - Check Main.storyboard")
      }
      return aboutWindowController
    }
  }
