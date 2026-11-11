//
//  FileOutputManagerTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/19/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import XCTest

class FileOutputManagerTests: XCTestCase {
  let directory = URL(fileURLWithPath: "/tmp/OnCue", isDirectory: true)

  func testUsesTheTimestampWhenTheNameIsFree() {
    let url = FileOutputManager.uniqueMovieURL(named: "2026-09-19 11.20.00", in: directory) { _ in false }
    XCTAssertEqual(url.lastPathComponent, "2026-09-19 11.20.00.mov")
  }

  func testNumbersFilesThatLandInTheSameSecond() {
    let taken: Set<String> = ["2026-09-19 11.20.00.mov", "2026-09-19 11.20.00 2.mov"]
    let url = FileOutputManager.uniqueMovieURL(named: "2026-09-19 11.20.00", in: directory) {
      taken.contains($0.lastPathComponent)
    }
    XCTAssertEqual(url.lastPathComponent, "2026-09-19 11.20.00 3.mov")
  }

  func testNamesBothDevicesAfterTheTime() {
    let name = FileOutputManager.movieName(timestamp: "2026-09-19 12.14.06", cameraName: "MacBook Pro Camera", microphoneName: "MacBook Pro Microphone")
    XCTAssertEqual(name, "2026-09-19 12.14.06 - MacBook Pro Camera + MacBook Pro Microphone")
  }

  func testNamesOnlyTheDeviceThatWasUsed() {
    XCTAssertEqual(FileOutputManager.movieName(timestamp: "2026-09-19 12.14.06", cameraName: nil, microphoneName: "USB Mic"),
                   "2026-09-19 12.14.06 - USB Mic")
    XCTAssertEqual(FileOutputManager.movieName(timestamp: "2026-09-19 12.14.06", cameraName: "Webcam", microphoneName: nil),
                   "2026-09-19 12.14.06 - Webcam")
    XCTAssertEqual(FileOutputManager.movieName(timestamp: "2026-09-19 12.14.06", cameraName: nil, microphoneName: nil),
                   "2026-09-19 12.14.06")
  }

  func testReplacesCharactersFileNamesCannotUse() {
    let name = FileOutputManager.movieName(timestamp: "2026-09-19 12.14.06", cameraName: "Cam A/B", microphoneName: "Mic: Left")
    XCTAssertEqual(name, "2026-09-19 12.14.06 - Cam A-B + Mic- Left")
  }

  func testLongNamesStayWithinTheFileSystemLimitWithRoomForANumber() {
    let longName = String(repeating: "Very Long Camera Name ", count: 20)
    let name = FileOutputManager.movieName(timestamp: "2026-09-19 12.14.06", cameraName: longName, microphoneName: "Mic")
    XCTAssertTrue(name.hasPrefix("2026-09-19 12.14.06 - Very Long Camera Name"))
    XCTAssertLessThanOrEqual("\(name) 999.mov".utf8.count, 255)
  }

  /// Spec 0024 renames a recording that lost frames to say how many seconds are missing, and that
  /// rename has to fit. A long device name used to eat the whole budget, the rename threw, the
  /// catch swallowed it, and the one signal saying the file is incomplete was gone.
  func testALongNameStillLeavesRoomToSayWhatWasLost() {
    let longName = String(repeating: "Very Long Camera Name ", count: 20)
    let name = FileOutputManager.movieName(timestamp: "2026-09-19 12.14.06", cameraName: longName, microphoneName: "Mic")
    let worstCase = "\(name) 999\(FrameLoss.longestNameSuffix).mov"
    XCTAssertLessThanOrEqual(worstCase.utf8.count, 255)
  }

  /// The reserved room has to cover the longest suffix the code can actually produce, not a
  /// typical one. A recording that ran for days loses more seconds than one that ran for minutes.
  func testTheReservedRoomCoversTheLongestSuffix() {
    let huge = FrameLoss.nameSuffix(longest: 100_000, missing: 9_999_999, written: 1, expected: 1_000_000)
    XCTAssertNotNil(huge)
    XCTAssertLessThanOrEqual((huge ?? "").utf8.count, FrameLoss.longestNameSuffix.utf8.count)
  }

  func testNumbersNamedFilesInTheSameSecond() {
    let base = "2026-09-19 12.14.06 - Webcam"
    let url = FileOutputManager.uniqueMovieURL(named: base, in: directory) { $0.lastPathComponent == "\(base).mov" }
    XCTAssertEqual(url.lastPathComponent, "2026-09-19 12.14.06 - Webcam 2.mov")
  }

  /// The still beside a recording (spec 0053) is never what Show Recordings selects.
  func testANewerStillDoesNotOutrankTheNewestMovie() {
    let older = Date(timeIntervalSince1970: 100), newer = Date(timeIntervalSince1970: 200)
    let movie = URL(fileURLWithPath: "/tmp/2026-09-25 17.40.12.mov")
    let still = URL(fileURLWithPath: "/tmp/2026-09-25 17.40.12.jpg")
    XCTAssertEqual(FileOutputManager.newestRecording(among: [(movie, older), (still, newer)]), movie)
  }

  /// A still is OnCue's own file to the rolling window, by the same timestamp rule.
  func testAStillOnCueWroteIsRecognised() {
    XCTAssertNotNil(FileOutputManager.recordingDate(fileName: "2026-09-25 17.40.12 - FaceTime HD Camera.jpg"))
  }

  func testPicksTheNewestRecordingByCreationDate() {
    let older = URL(fileURLWithPath: "/tmp/OnCue/2026-09-19 12.14.06 - Webcam.mov")
    let newer = URL(fileURLWithPath: "/tmp/OnCue/2026-09-19 12.14.06 - Webcam 2.mov")
    let notAMovie = URL(fileURLWithPath: "/tmp/OnCue/.DS_Store")
    let files = [(url: newer, created: Date(timeIntervalSince1970: 2_000)),
                 (url: older, created: Date(timeIntervalSince1970: 1_000)),
                 (url: notAMovie, created: Date(timeIntervalSince1970: 3_000))]
    XCTAssertEqual(FileOutputManager.newestRecording(among: files), newer)
  }

  func testNoRecordingsMeansNoNewest() {
    XCTAssertNil(FileOutputManager.newestRecording(among: []))
  }

  func testRecreatesAMissingFolder() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("OnCueTests-\(UUID().uuidString)")
    let manager = FileOutputManager(folder: folder)
    try FileManager.default.removeItem(at: folder)

    manager.ensureFolderExists()

    XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
    try FileManager.default.removeItem(at: folder)
  }

  func testNeverHandsOutTheSameNameTwice() {
    let manager = FileOutputManager()
    let first = manager.moviePath()
    let second = manager.moviePath()
    XCTAssertNotEqual(first.path, second.path)
  }

  // MARK: - Which files are OnCue's (spec 0029)

  func testARecordingOnCueWroteIsRecognised() {
    XCTAssertNotNil(FileOutputManager.recordingDate(fileName: "2026-09-20 01.39.21 - MacBook Pro Camera + MacBook Pro Microphone.mov"))
    XCTAssertNotNil(FileOutputManager.recordingDate(fileName: "2026-09-20 01.39.21.mov"))
  }

  /// Spec 0024 can add how much is missing, and that's still OnCue's file.
  func testAFileMarkedWithMissingSecondsIsStillOurs() {
    XCTAssertNotNil(FileOutputManager.recordingDate(fileName: "2026-09-20 01.39.21 - MacBook Pro Camera - 28s missing.mov"))
  }

  func testTheDateReadBackIsTheOneInTheName() {
    let date = FileOutputManager.recordingDate(fileName: "2026-09-20 01.39.21 - Camera.mov")
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
    XCTAssertEqual(formatter.string(from: date ?? Date.distantPast), "2026-09-20 01.39.21")
  }

  /// The one that matters: spec 0017 lets recordings go anywhere, including a Downloads folder
  /// full of somebody's downloads. Nothing that isn't ours may be mistaken for ours.
  func testSomebodyElsesFilesAreNotOurs() {
    for name in ["Screenshot 2026-09-20 at 01.39.21.png",
                 "invoice.pdf",
                 "OnCue-4.4.zip",
                 "2026-09-20.mov",
                 "notes 2026-09-20 01.39.21.mov",
                 "holiday video.mov",
                 ""] {
      XCTAssertNil(FileOutputManager.recordingDate(fileName: name), "\(name) was taken for ours")
    }
  }

  /// Renaming a recording takes it out of the set OnCue will delete, which is how "keep this one"
  /// works without any UI. Nothing here should get cleverer about renamed files.
  func testRenamingARecordingProtectsIt() {
    XCTAssertNil(FileOutputManager.recordingDate(fileName: "front door, Tuesday.mov"))
    XCTAssertNil(FileOutputManager.recordingDate(fileName: "KEEP 2026-09-20 01.39.21 - Camera.mov"))
  }

  // MARK: - How much room there is

  /// The numbers are real, read off a 1.8 TB external drive with 614 GB free: macOS answered 0 to
  /// the purgeable-space-aware question and 659 GB to the plain one. OnCue believed the 0, refused
  /// to record, and reported a full disk 29 times without ever attempting a write. Any recordings
  /// folder on an external drive was unusable.
  func testAnExternalVolumeIsNotReportedAsFull() {
    XCTAssertEqual(FileOutputManager.usableFreeBytes(importantUsage: 0, available: 659_717_439_488),
                   659_717_439_488)
  }

  /// On the boot disk both answer, and the plain one is smaller because it doesn't count space
  /// macOS could purge. Smaller is the safe direction for deciding whether to keep recording.
  func testTheConservativeAnswerWinsWhenBothAreThere() {
    XCTAssertEqual(FileOutputManager.usableFreeBytes(importantUsage: 1_367_865_428_919,
                                                     available: 984_014_667_776),
                   984_014_667_776)
  }

  /// A folder that isn't there answers nothing, and nothing is not zero: it means don't decide,
  /// rather than decide the disk is full.
  func testAnUnreachableFolderReportsNothingRatherThanNoRoom() {
    XCTAssertNil(FileOutputManager.usableFreeBytes(importantUsage: nil, available: nil))
  }

  func testItFallsBackWhenOnlyThePurgeableAnswerIsThere() {
    XCTAssertEqual(FileOutputManager.usableFreeBytes(importantUsage: 50_000, available: nil), 50_000)
  }

  // MARK: - Who can read the footage

  /// Spec 0017 lets recordings go anywhere, including somewhere every account on the Mac can read.
  /// A folder OnCue creates is its owner's alone.
  func testAFolderOnCueCreatesIsPrivate() throws {
    let folder = temporaryFolder("private")
    _ = FileOutputManager(folder: folder)

    let mode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as? NSNumber)
    XCTAssertEqual(mode.int16Value, 0o700)
  }

  /// A folder the user picked is theirs, so OnCue leaves its permissions exactly as it found them.
  func testAFolderTheUserAlreadyHadIsLeftAlone() throws {
    let folder = temporaryFolder("theirs")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o755])
    _ = FileOutputManager(folder: folder)

    let mode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: folder.path)[.posixPermissions] as? NSNumber)
    XCTAssertEqual(mode.int16Value, 0o755)
  }

  /// A recording is OnCue's own file, so it is kept to its owner even when the folder is not.
  func testAFinishedRecordingIsReadableOnlyByItsOwner() throws {
    let folder = temporaryFolder("perms")
    let file = folder.appendingPathComponent("2026-09-21 01.00.00 - Camera.mov")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(repeating: 0, count: 16).write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)

    FileOutputManager.makePrivate(file, permissions: 0o600)

    let mode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)
    XCTAssertEqual(mode.int16Value, 0o600)
  }

  // MARK: - A folder that comes and goes

  private func temporaryFolder(_ label: String) -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("OnCue-\(label)-\(UUID().uuidString)", isDirectory: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }

  /// A chosen folder can be on a drive that gets unplugged. The help says recordings go back to
  /// Movies when it isn't there, and a recording starting is when OnCue needs it.
  func testTheFolderIsRereadWhenItHasChanged() {
    let first = temporaryFolder("first"), second = temporaryFolder("second")
    let manager = FileOutputManager(folder: first)
    XCTAssertTrue(manager.refreshFolder(second))
    XCTAssertEqual(manager.oncuePath.standardizedFileURL.path, second.standardizedFileURL.path)
  }

  /// Re-reading the same folder has to be free. `setFolder` forgets the names handed out this
  /// session, and two recordings starting in the same second would then be given the same one.
  func testRereadingTheSameFolderKeepsNamesAlreadyHandedOut() {
    let folder = temporaryFolder("same")
    let manager = FileOutputManager(folder: folder)
    let date = Date(timeIntervalSince1970: 1_790_000_000)

    let first = manager.moviePath(cameraName: "Camera", date: date)
    XCTAssertFalse(manager.refreshFolder(folder), "nothing changed, so nothing should have been reset")
    let second = manager.moviePath(cameraName: "Camera", date: date)
    XCTAssertNotEqual(first.lastPathComponent, second.lastPathComponent)
  }

  // MARK: - Names something else already holds

  /// A dangling symlink reads as a free name to `fileExists`, which follows the link, and
  /// AVAssetWriter then writes the recording to wherever the link points. Verified: the file lands
  /// at the target, outside the recordings folder, out of reach of the rolling window and possibly
  /// on top of something else. Spec 0017 lets the folder be anywhere, so it is not always a folder
  /// only OnCue writes to.
  func testARecordingIsNotWrittenThroughAPlantedSymlink() throws {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("OnCue-links-\(UUID().uuidString)", isDirectory: true)
    let manager = FileOutputManager(folder: folder)
    defer { try? FileManager.default.removeItem(at: folder) }

    let date = Date(timeIntervalSince1970: 1_790_000_000)
    let stamp = manager.getCurrentTimeStampWOMiliseconds(dateToConvert: date)
    let taken = FileOutputManager.movieName(timestamp: stamp, cameraName: "Camera", microphoneName: nil) + ".mov"
    try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent(taken),
                                               withDestinationURL: folder.appendingPathComponent("nowhere.mov"))

    let chosen = FileOutputManager(folder: folder).moviePath(cameraName: "Camera", date: date)
    XCTAssertNotEqual(chosen.lastPathComponent, taken, "the recording would have followed the link")
  }

  /// A first launch: the recordings folder URL is built before the folder exists, which is what
  /// `RecordingsFolder.defaultFolder` does. `appendingPathComponent` asks the file system whether
  /// to mark the URL as a directory, so a folder that isn't there yet yields an unmarked URL, and
  /// every name built relative to it lands in the parent. That would put recordings loose in
  /// Movies, out of sight of Show Recordings and of the rolling window, which both look in the
  /// folder itself.
  func testRecordingsLandInTheFolderEvenOnAFirstLaunch() {
    let parent = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("OnCue-first-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: parent) }

    let folder = parent.appendingPathComponent("OnCue")
    XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "the folder must not exist yet")

    let url = FileOutputManager(folder: folder).moviePath(cameraName: "Camera")
    XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL.path,
                   folder.standardizedFileURL.path,
                   "the recording landed outside the recordings folder")
  }

  // MARK: - Scanning a real folder (spec 0029)

  /// Stands in for the manual check nobody ran: a folder holding OnCue's recordings alongside
  /// somebody else's files, scanned for real, with the deletion list taken from the result. A
  /// mistake here deletes files that were never OnCue's, so it's worth the temporary directory.
  func testOnlyOnCuesOwnFilesAreOfferedForDeletion() throws {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("OnCue-scan-\(UUID().uuidString)", isDirectory: true)
    let manager = FileOutputManager(folder: folder)
    defer { try? FileManager.default.removeItem(at: folder) }

    let ours = ["2026-09-18 01.39.21 - MacBook Pro Camera + MacBook Pro Microphone.mov",
                "2026-09-19 02.00.00.mov",
                "2026-09-20 03.00.00 - Webcam - 28s missing.mov"]
    let theirs = ["Screenshot 2026-09-20 at 01.39.21.png",
                  "invoice.pdf",
                  "OnCue-4.4.zip",
                  "front door, Tuesday.mov",
                  "holiday video.mov"]
    for name in ours + theirs {
      let data = Data(repeating: 0, count: 1024)
      try data.write(to: folder.appendingPathComponent(name))
    }

    let found = manager.ownRecordings()
    XCTAssertEqual(Set(found.map { $0.url.lastPathComponent }), Set(ours))
    XCTAssertTrue(found.allSatisfy { $0.bytes == 1024 }, "sizes came off the files, not from nowhere")

    // A limit small enough to want everything gone still can't reach anything that isn't ours.
    let deleting = DiskBudget.toDelete(found, limitBytes: 1).map { $0.url.lastPathComponent }
    XCTAssertTrue(Set(deleting).isDisjoint(with: Set(theirs)))
    XCTAssertEqual(deleting, ours, "oldest first, by the date in the name")
  }

  /// A folder whose name happens to parse as a recording is not a recording, and removeItem on a
  /// folder takes everything inside it. Only regular files are ever offered up.
  func testAFolderNamedLikeARecordingIsNotOneOfOurs() throws {
    let folder = temporaryFolder("dirs")
    let manager = FileOutputManager(folder: folder)

    let imposter = folder.appendingPathComponent("2026-09-18 01.00.00 - Camera.mov", isDirectory: true)
    try FileManager.default.createDirectory(at: imposter, withIntermediateDirectories: true)
    try Data(repeating: 0, count: 4096).write(to: imposter.appendingPathComponent("irreplaceable.txt"))
    // A symlink named like a recording is not ours either, whatever it points at.
    try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("2026-09-18 02.00.00 - Camera.mov"),
                                               withDestinationURL: imposter.appendingPathComponent("irreplaceable.txt"))
    let real = "2026-09-19 03.00.00 - Camera.mov"
    try Data(repeating: 0, count: 1024).write(to: folder.appendingPathComponent(real))

    let found = manager.ownRecordings()
    XCTAssertEqual(found.map { $0.url.lastPathComponent }, [real])
    XCTAssertEqual(DiskBudget.toDelete(found, limitBytes: 1).map { $0.url.lastPathComponent }, [real])
  }

}
