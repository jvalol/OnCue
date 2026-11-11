//
//  RecordingsFolder.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/19/26.
//  Copyright © 2026 Jake Van Alstyne
//

import Foundation

/// Where recordings are saved (spec 0017): `~/Movies/OnCue` unless another folder was chosen in
/// Settings. A chosen folder is kept as a security-scoped bookmark, since the sandbox only lets
/// OnCue write outside Movies to folders the user picked.
enum RecordingsFolder {
  static let bookmarkKey = "recordingsFolderBookmark"

  /// Marked as a directory explicitly: `appendingPathComponent` otherwise asks the file system,
  /// and on a first launch the folder isn't there yet to answer.
  static var defaultFolder: URL {
    FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
      .appendingPathComponent("OnCue", isDirectory: true)
  }

  /// The folder to record into, and whether that's the default because the chosen one is missing
  /// (a deleted folder, or a disk that isn't attached). The choice is kept either way, so it's used
  /// again when the folder comes back.
  static func inUse(chosen: URL?, chosenIsReachable: Bool, fallback: URL) -> (folder: URL, isFallback: Bool) {
    guard let chosen = chosen else {
      return (fallback, false)
    }
    return chosenIsReachable ? (chosen, false) : (fallback, true)
  }

  /// The folder sandbox access is currently held for, if any. Only ever one, since only one folder
  /// is in use. Main thread only, which is where every caller of `current()` runs.
  private static var accessing: URL?

  /// Which access to stop and which to start when the folder in use becomes `next`.
  ///
  /// `startAccessingSecurityScopedResource` takes a sandbox token that is only released by a
  /// matching stop or by the process exiting. Starting one per call leaked a token on every
  /// Settings open, Choose click, folder change and Show Recordings click, and a menu bar app runs
  /// for months. Holding at most one, and handing the old one back when the folder changes, is
  /// what makes Reset Folder actually revoke access rather than revoke it at the next quit.
  ///
  /// Compared by path, not by URL value: the same folder reaches this as differently built URLs,
  /// and `==` on URL answers no for those.
  static func accessChange(from current: URL?, to next: URL?) -> (stop: URL?, start: URL?) {
    if let current = current, let next = next,
      current.standardizedFileURL.path == next.standardizedFileURL.path {
      return (nil, nil)
    }
    return (stop: current, start: next)
  }

  /// Resolves what Settings chose, holding sandbox access to it. Nil if nothing was chosen or the
  /// bookmark no longer resolves, and in either case any access held is given back.
  static func resolveChosen(defaults: UserDefaults = .standard) -> URL? {
    guard let data = defaults.data(forKey: bookmarkKey) else {
      endAccess()
      return nil
    }
    var stale = false
    guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                             relativeTo: nil, bookmarkDataIsStale: &stale) else {
      endAccess()
      return nil
    }
    beginAccess(to: url)
    if stale, let refreshed = bookmark(for: url) {
      defaults.set(refreshed, forKey: bookmarkKey)
    }
    return url
  }

  private static func beginAccess(to url: URL) {
    let change = accessChange(from: accessing, to: url)
    change.stop?.stopAccessingSecurityScopedResource()
    guard let start = change.start else { return }
    // Only remember it if the start succeeded, so a later stop always matches a start. A bookmark
    // that isn't security-scoped resolves but doesn't grant anything.
    accessing = start.startAccessingSecurityScopedResource() ? start : nil
  }

  /// Gives back whatever access is held. Called when the choice goes away, so the grant does too.
  static func endAccess() {
    let change = accessChange(from: accessing, to: nil)
    change.stop?.stopAccessingSecurityScopedResource()
    accessing = nil
  }

  static func bookmark(for url: URL) -> Data? {
    try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
  }

  /// Remembers the folder the user picked.
  static func choose(_ url: URL, defaults: UserDefaults = .standard) {
    guard let data = bookmark(for: url) else { return }
    defaults.set(data, forKey: bookmarkKey)
  }

  /// Back to `~/Movies/OnCue`, forgetting the choice and giving its access back now rather than
  /// at the next quit.
  static func reset(defaults: UserDefaults = .standard) {
    defaults.removeObject(forKey: bookmarkKey)
    endAccess()
  }

  /// Whether OnCue can actually write to a folder, found out by writing to it (spec 0034).
  ///
  /// Nothing short of trying answers this. A Time Machine destination, a volume owned by root, a
  /// read-only mount and a folder someone revoked permission on all fail for different reasons and
  /// all fail the same way when you attempt a write. Reading permissions and guessing would get
  /// each of them wrong in its own way.
  ///
  /// The file is removed again, and any left by an earlier run go with it, so a folder OnCue can
  /// write to is left exactly as it was found. A process killed between the write and the delete
  /// would otherwise leave one behind for good: the name carries a UUID, so they would pile up
  /// rather than overwrite, and nothing else would ever clear them. OnCue's own scan skips hidden
  /// files and wouldn't recognise the name anyway, so the rolling window can't see them either.
  ///
  /// Written plainly rather than atomically. An atomic write puts a temporary file alongside and
  /// renames it, touching the folder twice to answer a question one write answers, and nothing
  /// reads this file.
  static func canWrite(to folder: URL) -> Bool {
    sweepProbes(from: folder)
    let probe = folder.appendingPathComponent("\(probePrefix)\(UUID().uuidString)")
    guard (try? Data().write(to: probe)) != nil else { return false }
    try? FileManager.default.removeItem(at: probe)
    return true
  }

  static let probePrefix = ".oncue-write-test-"

  /// Clears probes an earlier run didn't get to. Only files with this exact prefix, so it can never
  /// touch a recording or anything else in a folder OnCue doesn't own.
  private static func sweepProbes(from folder: URL) {
    let contents = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                options: [])
    for url in contents ?? [] where url.lastPathComponent.hasPrefix(probePrefix) {
      try? FileManager.default.removeItem(at: url)
    }
  }

  /// What the folder row in Settings has to say (spec 0034).
  ///
  /// Three states, not two. The third is the one that hid a Time Machine volume: the chosen folder
  /// is right there and reachable, so nothing falls back, and recordings fail while the row looks
  /// perfectly normal.
  enum FolderState: Equatable {
    /// Recordings are going to the folder that was chosen, or to the default.
    case inUse(URL)
    /// The chosen folder isn't available, so recordings are going to `using` instead.
    case fellBack(using: URL, chosen: URL)
    /// The chosen folder is there and OnCue can't write to it.
    case notWritable(URL)
  }

  /// `chosen` is what Settings picked, nil when nothing was. `inUse` is where recordings actually
  /// go. `writable` is the answer from `canWrite`, which the caller does because it touches disk.
  static func state(chosen: URL?, inUse: URL, isFallback: Bool, writable: Bool) -> FolderState {
    if isFallback, let chosen = chosen {
      return .fellBack(using: inUse, chosen: chosen)
    }
    return writable ? .inUse(inUse) : .notWritable(inUse)
  }

  static func shortPath(_ url: URL) -> String {
    return (url.path as NSString).abbreviatingWithTildeInPath
  }

  /// What sits under the path: what the path is when all is well, and what's wrong when it isn't.
  /// The row was a bare path with two buttons and no words saying what it was for.
  static func note(for state: FolderState) -> String {
    switch state {
    case .inUse:
      return String(localized: "Recordings are saved here.", comment: "Settings, under the recordings folder")
    case let .fellBack(_, chosen):
      return String(localized: "\(shortPath(chosen)) isn't available, so recordings are going here for now.", comment: "Settings, under the recordings folder; the argument is the chosen folder")
    case .notWritable:
      return String(localized: "OnCue isn't allowed to write here, so recordings will fail. Choose somewhere else.", comment: "Settings, under the recordings folder")
    }
  }

  /// Whether the note is telling you something is wrong, as opposed to saying what the path is.
  /// One line carries both, so its colour is the only thing that tells them apart.
  static func isWarning(_ state: FolderState) -> Bool {
    switch state {
    case .inUse: return false
    case .fellBack, .notWritable: return true
    }
  }

  /// The folder to use now, with whether it's the fallback.
  static func current(defaults: UserDefaults = .standard) -> (folder: URL, isFallback: Bool) {
    let chosen = resolveChosen(defaults: defaults)
    let reachable = chosen.map { (try? $0.checkResourceIsReachable()) ?? false } ?? false
    return inUse(chosen: chosen, chosenIsReachable: reachable, fallback: defaultFolder)
  }
}
