//
//  FileOutputManager.swift
//  OnCue
//
//  Created by Jake Van Alstyne on 1/31/20.
//  Copyright © 2020 Jake Van Alstyne
//

import Cocoa
import AVFoundation

class FileOutputManager: NSObject {
  /// Where recordings are written now; follows the folder chosen in Settings (spec 0017).
  private(set) var oncuePath: URL
  /// Every path handed out this session. A file may not be on disk yet when the next name is chosen,
  /// and two recordings sharing a name couldn't be told apart when they finish.
  private var issuedPaths = Set<String>()

  /// `~/Movies/OnCue`, unless another folder was chosen in Settings.
  static var defaultFolder: URL {
    RecordingsFolder.current().folder
  }

  /// Tests pass a temporary folder.
  init(folder: URL = FileOutputManager.defaultFolder) {
    oncuePath = folder
    super.init()
    ensureFolderExists()
  }

  /// Re-reads where recordings go, for a chosen folder that came back or went away since the last
  /// recording: an external drive, a share, a folder that syncs. Returns whether it moved.
  ///
  /// Does nothing when the folder is the same, because `setFolder` forgets the names handed out
  /// this session and two recordings starting in the same second would then be given the same one.
  @discardableResult
  func refreshFolder(_ folder: URL) -> Bool {
    guard folder.standardizedFileURL.path != oncuePath.standardizedFileURL.path else { return false }
    setFolder(folder)
    return true
  }

  /// The folder changed in Settings; later recordings go to the new one.
  func setFolder(_ folder: URL) {
    oncuePath = folder
    issuedPaths.removeAll()
    ensureFolderExists()
  }

  /// Creates the recordings folder if it's missing, as it can be if it was deleted since launch.
  ///
  /// A folder OnCue makes is for its owner only. `~/Movies` is already private, but spec 0017 lets
  /// recordings go anywhere, and a folder created under something like `/Users/Shared` would
  /// otherwise be readable by everyone with an account on the Mac. A folder the user picked
  /// themselves is left exactly as they set it: OnCue sets permissions on what it creates, not on
  /// what it finds.
  func ensureFolderExists() {
    guard !FileManager.default.fileExists(atPath: oncuePath.path) else { return }
    do {
      try FileManager.default.createDirectory(at: oncuePath, withIntermediateDirectories: true, attributes: nil)
      FileOutputManager.makePrivate(oncuePath, permissions: 0o700)
    } catch {
      print(error.localizedDescription)
    }
  }

  /// Takes group and other off something OnCue made, where the file system has such a notion.
  ///
  /// Set afterwards rather than passed to the create call, so a volume that has no POSIX
  /// permissions at all, an exFAT card or a share, still gets its folder and its recordings. There
  /// is nothing to enforce on those volumes anyway, which is worth knowing before putting footage
  /// on one.
  static func makePrivate(_ url: URL, permissions: Int) {
    try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
  }

  /// The most recently created recording in the folder, if any.
  func newestRecording() -> URL? {
    let urls = (try? FileManager.default.contentsOfDirectory(at: oncuePath, includingPropertiesForKeys: [.creationDateKey])) ?? []
    let files = urls.compactMap { url -> (url: URL, created: Date)? in
      guard let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate else { return nil }
      return (url, created)
    }
    return FileOutputManager.newestRecording(among: files)
  }

  /// By creation date, not name: a device-named file and a numbered one from the same second
  /// don't sort by time.
  class func newestRecording(among files: [(url: URL, created: Date)]) -> URL? {
    return files
      .filter { $0.url.pathExtension.lowercased() == "mov" }
      .max { $0.created < $1.created }?
      .url
  }

  func moviePath(cameraName: String? = nil, microphoneName: String? = nil, date: Date = Date()) -> URL {
    let nowTimeStamp = self.getCurrentTimeStampWOMiliseconds(dateToConvert: date)
    let name = FileOutputManager.movieName(timestamp: nowTimeStamp, cameraName: cameraName, microphoneName: microphoneName)
    let url = FileOutputManager.uniqueMovieURL(named: name, in: oncuePath) {
      self.issuedPaths.contains($0.path) || FileOutputManager.somethingIsThere(at: $0)
    }
    issuedPaths.insert(url.path)
    return url
  }

  /// Whether the name is taken, by anything at all, including a symlink pointing nowhere.
  ///
  /// `fileExists` follows symlinks, so a dangling one reads as a free name and AVAssetWriter then
  /// writes the recording to wherever the link points: outside the recordings folder, beyond the
  /// reach of the rolling window, and possibly over something else. `attributesOfItem` is an
  /// lstat, so it sees the link itself and the name is skipped instead.
  private class func somethingIsThere(at url: URL) -> Bool {
    return (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
  }

  /// The start time, then the devices recorded from: "2026-09-19 12.14.06 - Camera + Microphone".
  /// The time comes first so recordings sort by time in Finder.
  class func movieName(timestamp: String, cameraName: String?, microphoneName: String?) -> String {
    let devices = [cameraName, microphoneName].compactMap { $0 }.map(fileSafe).filter { !$0.isEmpty }
    guard !devices.isEmpty else {
      return timestamp
    }
    var name = "\(timestamp) - \(devices.joined(separator: " + "))"
    // File names are limited to 255 bytes. Leave room for a " 999" number, the ".mov" extension,
    // and spec 0024's " - 28s missing", which is appended by renaming the finished file. Without
    // that last allowance a long device name filled the budget, the rename threw, and the one
    // thing saying the recording is incomplete never appeared.
    let limit = 255 - " 999.mov".utf8.count - FrameLoss.longestNameSuffix.utf8.count
    while name.utf8.count > limit {
      name.removeLast()
    }
    return name.trimmingCharacters(in: .whitespaces)
  }

  /// Free space where recordings go, or nil if it can't be read (spec 0029).
  func freeBytes() -> Int64? {
    let values = try? oncuePath.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                                         .volumeAvailableCapacityKey])
    return FileOutputManager.usableFreeBytes(importantUsage: values?.volumeAvailableCapacityForImportantUsage,
                                             available: values?.volumeAvailableCapacity.map(Int64.init))
  }

  /// Which of the two answers macOS gives to believe.
  ///
  /// `volumeAvailableCapacityForImportantUsage` knows about purgeable space, which is why 0029
  /// reached for it, and on an external volume it answers 0 with a straight face. A drive with 614
  /// GB free reported none, so OnCue refused to record and said the disk was full, over and over,
  /// having never attempted a write. Any recordings folder on an external drive was unusable.
  ///
  /// `volumeAvailableCapacity` is right on every volume, and being the smaller number on the boot
  /// disk is the safe direction for something deciding whether to keep recording.
  static func usableFreeBytes(importantUsage: Int64?, available: Int64?) -> Int64? {
    return available ?? importantUsage
  }

  /// The recordings OnCue wrote, by the names it writes. Everything else in the folder belongs to
  /// someone else, which matters because spec 0017 lets that folder be anywhere.
  func ownRecordings() -> [DiskBudget.Recording] {
    let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
    guard let urls = try? FileManager.default.contentsOfDirectory(at: oncuePath,
                                                                  includingPropertiesForKeys: keys,
                                                                  options: [.skipsHiddenFiles]) else {
      return []
    }
    return urls.compactMap { url in
      guard let started = FileOutputManager.recordingDate(fileName: url.lastPathComponent) else { return nil }
      // A recording is a file. A folder that happens to be named like one is not ours, and
      // removeItem on a folder takes everything inside it. Symlinks are not ours either.
      let values = try? url.resourceValues(forKeys: Set(keys))
      guard values?.isRegularFile == true else { return nil }
      return DiskBudget.Recording(url: url, started: started, bytes: Int64(values?.fileSize ?? 0))
    }
  }

  /// The date in a name OnCue wrote, or nil if this isn't one of ours (spec 0029).
  ///
  /// This is what keeps the rolling window from touching anything else in the folder. Spec 0017
  /// lets recordings go anywhere, including a Downloads folder full of somebody's downloads, so
  /// "the oldest file in the folder" would be dangerous. A file only counts as OnCue's if its name
  /// still starts with a timestamp in the format `movieName` writes.
  ///
  /// The useful side effect, and it's deliberate: renaming a recording takes it out of the set
  /// OnCue will ever delete. That's how "keep this one" works, with no UI needed, so nothing here
  /// should get cleverer about recognising files that have been renamed.
  class func recordingDate(fileName: String) -> Date? {
    let name = (fileName as NSString).deletingPathExtension
    let stamp = String(name.prefix(19))
    guard stamp.count == 19 else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
    guard let date = formatter.date(from: stamp) else { return nil }
    // Either the timestamp alone, or the timestamp then " - " and the devices.
    let rest = name.dropFirst(19)
    guard rest.isEmpty || rest.hasPrefix(" - ") else { return nil }
    return date
  }

  /// "/" can't appear in a file name and ":" shows as "/" in Finder, so both become "-".
  private class func fileSafe(_ deviceName: String) -> String {
    return deviceName
      .replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: ":", with: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Names are to the second, and a file restarted after an interruption can land in the same
  /// second as the one before it. The recorder won't overwrite, so number the later ones.
  ///
  /// Built by appending to the folder rather than relative to it. `URL(fileURLWithPath:relativeTo:)`
  /// resolves against the folder's parent unless the folder URL is marked as a directory, and
  /// whether it is marked depends on the folder existing when the URL was built. On a first launch
  /// it doesn't, so recordings landed loose in Movies, where neither Show Recordings nor the
  /// rolling window would find them. Appending also keeps these URLs absolute, so they compare
  /// with URLs a directory scan returns.
  class func uniqueMovieURL(named name: String, in directory: URL, exists: (URL) -> Bool) -> URL {
    var url = directory.appendingPathComponent("\(name).mov")
    var number = 2
    while exists(url) {
      url = directory.appendingPathComponent("\(name) \(number).mov")
      number += 1
    }
    return url
  }

  internal func getCurrentTimeStampWOMiliseconds(dateToConvert: Date) -> String {
    let objDateformat: DateFormatter = DateFormatter()
    // Fixed-format timestamp, so pin the locale; the user's calendar and numbering system would change it.
    // Colons display as slashes in Finder, so separate the time with periods like macOS screenshots do.
    objDateformat.locale = Locale(identifier: "en_US_POSIX")
    objDateformat.dateFormat = "yyyy-MM-dd HH.mm.ss"
    let strTime: String = objDateformat.string(from: dateToConvert as Date)
    return strTime
  }
}
