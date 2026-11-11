//
//  FreshStart.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/22/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import Foundation

/// The first launch into an empty container is also what an update looks like once the bundle ID
/// has changed (spec 0037): every setting at its default, the chosen folder gone, arm at login off.
/// The sandbox won't let the app read the old container, so it can't tell the two apart and doesn't
/// try. It says so, once, until someone has looked: Settings opened, or OnCue armed. Stored rather
/// than kept in memory, so a launch nobody looked at doesn't use the notice up.
struct FreshStart {
  static let key = "freshStartNoticePending"

  let defaults: UserDefaults

  static let app = FreshStart(defaults: .standard)

  /// For the first launch into this container, and only that one. A container that already has
  /// settings never goes through here, so it never shows the notice.
  func begin() {
    defaults.set(true, forKey: FreshStart.key)
  }

  var isPending: Bool {
    defaults.bool(forKey: FreshStart.key)
  }

  /// The person has looked. Once cleared it stays cleared.
  func clear() {
    defaults.set(false, forKey: FreshStart.key)
  }
}
