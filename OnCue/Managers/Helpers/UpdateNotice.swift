//
//  UpdateNotice.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 10/2/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import Foundation

/// One line after an update, pointing at the changelog (spec 0058). OnCue remembers the version
/// that last ran; a launch under a different one owes the person a link, which stays until it's
/// clicked or the next update replaces it. A launch with no remembered version into a container
/// that isn't fresh is an update from before this was written: for the store, 3.0.3.
struct UpdateNotice {
  static let lastRunKey = "lastRunVersion"
  static let pendingKey = "updateNoticePendingFor"
  static let changelog = URL(string: "https://oncue.jva.lol/changelog/")!
  /// What the pending key holds for an update whose previous version isn't known.
  static let olderMarker = "older"

  enum Update: Equatable {
    /// From a version that never recorded itself, which for the store is 3.0.3.
    case fromOlder
    case to(String)
  }

  let defaults: UserDefaults

  static let app = UpdateNotice(defaults: .standard)

  /// The pure rule. A fresh container is 0037's to speak about; the same version is no update.
  static func check(running: String, lastRun: String?, fresh: Bool) -> Update? {
    guard !fresh, !running.isEmpty else { return nil }
    guard let last = lastRun else { return .fromOlder }
    return last == running ? nil : .to(running)
  }

  /// At launch: remembers this version, and if it's an update, what the line is about. A line
  /// still pending from the last update is replaced, not added to.
  func note(running: String, fresh: Bool) {
    let last = defaults.string(forKey: UpdateNotice.lastRunKey)
    if let update = UpdateNotice.check(running: running, lastRun: last, fresh: fresh) {
      switch update {
      case .fromOlder: defaults.set(UpdateNotice.olderMarker, forKey: UpdateNotice.pendingKey)
      case .to(let version): defaults.set(version, forKey: UpdateNotice.pendingKey)
      }
    }
    if !running.isEmpty {
      defaults.set(running, forKey: UpdateNotice.lastRunKey)
    }
  }

  /// The line owed, if any.
  var pending: Update? {
    // Empty counts as none: the store renders override the key with "" to keep a pending line
    // from the user's own defaults out of the pictures (0061).
    guard let stored = defaults.string(forKey: UpdateNotice.pendingKey), !stored.isEmpty else { return nil }
    return stored == UpdateNotice.olderMarker ? .fromOlder : .to(stored)
  }

  /// The link was clicked.
  func clear() {
    defaults.removeObject(forKey: UpdateNotice.pendingKey)
  }

  /// "v4-19": the id on the changelog's heading for a version.
  static func anchor(for version: String) -> String {
    return "v" + version.replacingOccurrences(of: ".", with: "-")
  }

  /// The changelog at this version's entry, or its top for an update from an unknown version.
  static func url(for update: Update, running: String) -> URL {
    switch update {
    case .fromOlder:
      return URL(string: "#" + anchor(for: running), relativeTo: changelog)?.absoluteURL ?? changelog
    case .to(let version):
      return URL(string: "#" + anchor(for: version), relativeTo: changelog)?.absoluteURL ?? changelog
    }
  }
}
