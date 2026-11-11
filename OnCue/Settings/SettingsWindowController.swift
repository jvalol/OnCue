//
//  SettingsWindowController.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 2/15/20.
//  Copyright © 2020 Jake Van Alstyne
//

import Cocoa

class SettingsWindowController: NSWindowController {

  override func windowDidLoad() {
    super.windowDidLoad()
    self.window?.level = .floating
  }
}

extension SettingsWindowController {
  static func freshController() -> SettingsWindowController {
    let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
    let identifier = NSStoryboard.SceneIdentifier("SettingsWindowController")
    guard let settingsWindowController = storyboard.instantiateController(withIdentifier: identifier) as? SettingsWindowController else {
      fatalError("Why cant I find SettingsWindowController? - Check Main.storyboard")
    }
    return settingsWindowController
  }
}
