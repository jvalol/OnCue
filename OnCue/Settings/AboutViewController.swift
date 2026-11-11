//
//  AboutViewController.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 4/11/20.
//  Copyright © 2020 Jake Van Alstyne. All rights reserved.
//

import Cocoa

class AboutViewController: NSViewController {
  @IBOutlet var versionLabel: NSTextField?

  override func viewDidLoad() {
    super.viewDidLoad()

    versionLabel?.stringValue = String(localized: "Version \(Bundle.main.releaseVersionNumber!)", comment: "About window; the argument is the version number")
  }
}

extension Bundle {
  var releaseVersionNumber: String? {
    return infoDictionary?["CFBundleShortVersionString"] as? String
  }
  var buildVersionNumber: String? {
    return infoDictionary?["CFBundleVersion"] as? String
  }
}
