//
//  DiskBudget.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 9/20/26.
//  Copyright © 2026 Jake Van Alstyne
//

import Foundation

/// How much disk recordings are allowed to use (spec 0029). OnCue used to write until the disk was
/// full and then stop being a security camera; spec 0027 made that visible, which is not the same
/// as preventing it.
///
/// Two rules, because they're about different things. Stopping is about the Mac and is always on.
/// The rolling window is about OnCue's own footprint, deletes footage, and only happens because
/// someone asked for it.
enum DiskBudget {
  /// Headroom kept free wherever recordings go. A recording lasts as long as the activity does, so
  /// the next one's size is unknowable and this has to be conservative rather than clever.
  static let headroomBytes: Int64 = 2 * 1024 * 1024 * 1024

  /// The largest window Settings will accept, and so the largest one OnCue honours. Well past any
  /// disk it would be recording to.
  static let maximumLimitGB = 10_000

  /// The window in bytes, or nil when it's off.
  ///
  /// Clamped, because the number comes from a preference and a preference is a file any process
  /// running as the user can write. Settings won't take a number this big, but nothing stops one
  /// being written straight into defaults, and multiplying it out traps on overflow. A camera that
  /// dies the next time a recording finishes is worse than a limit that got clamped.
  static func limitBytes(gigabytes: Int) -> Int64? {
    guard gigabytes > 0 else { return nil }
    return Int64(min(gigabytes, maximumLimitGB)) * 1024 * 1024 * 1024
  }

  /// A recording OnCue wrote: when it started, what it takes up, and where.
  struct Recording: Equatable {
    let url: URL
    let started: Date
    let bytes: Int64
  }

  /// Whether there's room to start recording. Below the headroom OnCue stops deliberately, which
  /// beats writing into a full disk and failing.
  static func hasRoomToRecord(freeBytes: Int64) -> Bool {
    return freeBytes >= headroomBytes
  }

  /// Whether the recording in progress should roll into a new file (spec 0031).
  ///
  /// Deleting can't help while the file that's over the limit is the one still being written: it
  /// grows whatever else goes. 0029 chose to do nothing in that case, which was right for a file
  /// that had already finished. A growing one is different, because nothing stops it and the limit
  /// quietly stops being true for as long as the event lasts.
  ///
  /// Rolling makes it true again. The recording continues in a new file, the one that just closed
  /// becomes deletable like any other, and a long event leaves roughly the most recent limit's
  /// worth.
  ///
  /// Only the files being written are weighed, not the folder, and deliberately: once they alone
  /// are over the limit, no amount of deleting around them can bring the total under. Asking about
  /// the whole folder instead would make this depend on whether trimming had already run.
  ///
  /// `inProgressBytes` is the total of them, which is two files with two cameras, because the limit
  /// is on what OnCue's recordings add up to and a recording is both cameras.
  static func shouldRoll(inProgressBytes: Int64, limitBytes: Int64?) -> Bool {
    guard let limit = limitBytes, limit > 0 else { return false }
    return inProgressBytes > limit
  }

  /// What the rolling window would delete to get back under `limitBytes`, oldest first.
  ///
  /// `keeping` is never offered up: those are the files being written now, and deleting one under
  /// an open writer would lose the very thing OnCue is recording. Two cameras means two of them.
  /// Returns nothing when the window is off, when there's nothing over the limit, or when the only
  /// thing over it is a recording in progress.
  ///
  /// Standardized paths, not URLs. The recorder's URL and a directory scan's URL for the same file
  /// are different values, so comparing URLs matched nothing and the guard protected nothing.
  static func toDelete(_ recordings: [Recording], limitBytes: Int64?,
                       keeping: Set<String> = []) -> [Recording] {
    guard let limit = limitBytes, limit > 0 else { return [] }
    var total = recordings.reduce(Int64(0)) { $0 + $1.bytes }
    guard total > limit else { return [] }

    // A recording and its still (spec 0053) go together or not at all, so the window weighs
    // events, not files. An event with a file being written now is never offered up, still
    // included: a still without its movie, or a movie without its still, is what this avoids.
    let events = Dictionary(grouping: recordings) { eventKey(for: $0.url) }
      .values
      .filter { event in !event.contains { keeping.contains($0.url.standardizedFileURL.path) } }
      .sorted { ($0.map { $0.started }.min() ?? .distantPast) < ($1.map { $0.started }.min() ?? .distantPast) }

    var deleting: [Recording] = []
    for event in events {
      guard total > limit else { break }
      // The movie first, then its still, so a delete cut short leaves the still to fall with it.
      let files = event.sorted { $0.url.pathExtension.lowercased() == "mov" && $1.url.pathExtension.lowercased() != "mov" }
      deleting.append(contentsOf: files)
      total -= files.reduce(Int64(0)) { $0 + $1.bytes }
    }
    return deleting
  }

  /// What makes a movie and its still one event: the folder and the name without the extension,
  /// and without 0024's " - 28s missing", which is put on the movie after the still was named.
  static func eventKey(for url: URL) -> String {
    let name = url.deletingPathExtension().lastPathComponent
    let base = name.replacingOccurrences(of: " - [0-9]+s missing$", with: "", options: .regularExpression)
    return url.deletingLastPathComponent().standardizedFileURL.path + "/" + base
  }
}
