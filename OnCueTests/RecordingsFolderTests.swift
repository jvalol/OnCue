//
//  RecordingsFolderTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/19/26.
//  Copyright © 2026 Jake Van Alstyne
//

import XCTest

class RecordingsFolderTests: XCTestCase {
  let chosen = URL(fileURLWithPath: "/Volumes/Backup/OnCue", isDirectory: true)
  let fallback = URL(fileURLWithPath: "/Users/jake/Movies/OnCue", isDirectory: true)

  func testTheDefaultFolderWhenNothingWasChosen() {
    let result = RecordingsFolder.inUse(chosen: nil, chosenIsReachable: false, fallback: fallback)
    XCTAssertEqual(result.folder, fallback)
    XCTAssertFalse(result.isFallback)
  }

  func testTheChosenFolderWhenItsThere() {
    let result = RecordingsFolder.inUse(chosen: chosen, chosenIsReachable: true, fallback: fallback)
    XCTAssertEqual(result.folder, chosen)
    XCTAssertFalse(result.isFallback)
  }

  func testFallsBackWhenTheChosenFolderIsMissing() {
    let result = RecordingsFolder.inUse(chosen: chosen, chosenIsReachable: false, fallback: fallback)
    XCTAssertEqual(result.folder, fallback)
    XCTAssertTrue(result.isFallback)
  }

  func testChoosingAndResettingRemembersAndForgets() {
    let suite = "OnCueTests.RecordingsFolder"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }

    RecordingsFolder.choose(FileManager.default.temporaryDirectory, defaults: defaults)
    XCTAssertNotNil(defaults.data(forKey: RecordingsFolder.bookmarkKey))

    RecordingsFolder.reset(defaults: defaults)
    XCTAssertNil(defaults.data(forKey: RecordingsFolder.bookmarkKey))
    XCTAssertNil(RecordingsFolder.resolveChosen(defaults: defaults))
  }

  // MARK: - Whether OnCue can write there (spec 0034)

  /// A real write, because nothing short of trying answers it. A Time Machine destination, a
  /// volume owned by root and a read-only mount all fail differently and all fail the same way
  /// when you attempt a write.
  func testAWritableFolderSaysSoAndIsLeftAsItWasFound() throws {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("OnCue-write-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: folder) }

    XCTAssertTrue(RecordingsFolder.canWrite(to: folder))
    let leftBehind = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    XCTAssertEqual(leftBehind, [], "the probe file has to be cleaned up")
  }

  /// A folder that exists and can't be written to. This is the shape of the Time Machine volume
  /// that started spec 0034: reachable, so nothing falls back, and every recording fails.
  func testAnUnwritableFolderSaysSo() throws {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("OnCue-readonly-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    addTeardownBlock {
      try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
      try? FileManager.default.removeItem(at: folder)
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)

    XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path), "it's there, it just can't be written to")
    XCTAssertFalse(RecordingsFolder.canWrite(to: folder))
  }

  /// A run killed between writing the probe and deleting it leaves one behind, and the UUID in the
  /// name means they pile up rather than overwrite. The next check clears them.
  func testStaleProbesFromAnEarlierRunAreSweptUp() throws {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("OnCue-sweep-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: folder) }

    for _ in 0..<3 {
      try Data().write(to: folder.appendingPathComponent("\(RecordingsFolder.probePrefix)\(UUID().uuidString)"))
    }
    let keep = "2026-09-21 01.00.00 - Camera.mov"
    try Data(repeating: 0, count: 8).write(to: folder.appendingPathComponent(keep))

    XCTAssertTrue(RecordingsFolder.canWrite(to: folder))

    let left = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    XCTAssertEqual(left, [keep], "probes go, everything else stays")
  }

  func testAFolderThatIsNotThereCannotBeWrittenTo() {
    XCTAssertFalse(RecordingsFolder.canWrite(to: URL(fileURLWithPath: "/Volumes/Nope Not Mounted/OnCue", isDirectory: true)))
  }

  // MARK: - What the folder row says (spec 0034)

  func testTheOrdinaryCaseIsOneFolderInUse() {
    XCTAssertEqual(RecordingsFolder.state(chosen: chosen, inUse: chosen, isFallback: false, writable: true),
                   .inUse(chosen))
    XCTAssertEqual(RecordingsFolder.state(chosen: nil, inUse: fallback, isFallback: false, writable: true),
                   .inUse(fallback))
  }

  /// Naming the chosen folder is the point: without it you can't tell whether to plug a drive back
  /// in or press Reset, which is the only decision available at that moment.
  func testFallingBackNamesBothFolders() {
    XCTAssertEqual(RecordingsFolder.state(chosen: chosen, inUse: fallback, isFallback: true, writable: true),
                   .fellBack(using: fallback, chosen: chosen))
  }

  /// The state that hid a Time Machine volume. Reachable, so nothing falls back, and without the
  /// write test it looks exactly like the ordinary case while every recording fails.
  func testAReachableFolderThatCannotBeWrittenToIsItsOwnState() {
    XCTAssertEqual(RecordingsFolder.state(chosen: chosen, inUse: chosen, isFallback: false, writable: false),
                   .notWritable(chosen))
  }

  /// Falling back wins over unwritable: recordings are going somewhere else entirely, which is the
  /// more important thing to say, and the chosen folder's writability is moot while it's away.
  func testFallingBackIsReportedEvenIfTheChosenFolderIsAlsoUnwritable() {
    XCTAssertEqual(RecordingsFolder.state(chosen: chosen, inUse: fallback, isFallback: true, writable: false),
                   .fellBack(using: fallback, chosen: chosen))
  }

  /// The note carries two different kinds of message on one line, so its colour is the only thing
  /// telling them apart. Saying what the path is must never look like a warning, and a warning
  /// must never look like a caption.
  func testOnlyTheProblemStatesReadAsWarnings() {
    XCTAssertFalse(RecordingsFolder.isWarning(.inUse(fallback)))
    XCTAssertTrue(RecordingsFolder.isWarning(.fellBack(using: fallback, chosen: chosen)))
    XCTAssertTrue(RecordingsFolder.isWarning(.notWritable(chosen)))
  }

  /// Every state says something, including the ordinary one, because the row had no words at all
  /// saying it was where recordings go.
  func testEveryStateSaysSomething() {
    for state: RecordingsFolder.FolderState in [.inUse(fallback),
                                                .fellBack(using: fallback, chosen: chosen),
                                                .notWritable(chosen)] {
      XCTAssertFalse(RecordingsFolder.note(for: state).isEmpty, "\(state) said nothing")
    }
  }

  /// The one that matters when something is wrong: you cannot tell whether to plug a drive back in
  /// or press Reset unless the folder you chose is named.
  func testFallingBackNamesTheFolderYouChose() {
    let note = RecordingsFolder.note(for: .fellBack(using: fallback, chosen: chosen))
    XCTAssertTrue(note.contains(RecordingsFolder.shortPath(chosen)), note)
  }

  // MARK: - Holding sandbox access to the chosen folder

  /// Every start holds a sandbox token until the process exits, so resolving the same folder again
  /// must not take a second one. Settings, Show Recordings and a folder change all resolve, and a
  /// menu bar app runs for months.
  func testResolvingTheSameFolderAgainDoesNotTakeAnotherAccess() {
    let change = RecordingsFolder.accessChange(from: chosen, to: chosen)
    XCTAssertNil(change.start)
    XCTAssertNil(change.stop)
  }

  func testTheFirstFolderStartsAccess() {
    let change = RecordingsFolder.accessChange(from: nil, to: chosen)
    XCTAssertEqual(change.start, chosen)
    XCTAssertNil(change.stop)
  }

  /// Changing folders hands the old access back rather than keeping both.
  func testChangingFolderStopsTheOldAccess() {
    let other = URL(fileURLWithPath: "/Volumes/Other/OnCue", isDirectory: true)
    let change = RecordingsFolder.accessChange(from: chosen, to: other)
    XCTAssertEqual(change.stop, chosen)
    XCTAssertEqual(change.start, other)
  }

  /// Reset has to actually give the grant back. Until it does, the app keeps read-write access to
  /// a folder the user took away, for as long as it stays running.
  func testResettingStopsAccessWithoutStartingAnother() {
    let change = RecordingsFolder.accessChange(from: chosen, to: nil)
    XCTAssertEqual(change.stop, chosen)
    XCTAssertNil(change.start)
  }

  func testNothingToDoWhenThereWasNoChosenFolder() {
    let change = RecordingsFolder.accessChange(from: nil, to: nil)
    XCTAssertNil(change.stop)
    XCTAssertNil(change.start)
  }

  /// The same folder can arrive as a different URL value, which is how the in-progress recording
  /// guard in DiskBudget was quietly broken. Compare where it points, not how it was built.
  func testTheSameFolderIsRecognisedHoweverTheURLWasBuilt() {
    let built = URL(fileURLWithPath: "OnCue", relativeTo: URL(fileURLWithPath: "/Volumes/Backup", isDirectory: true))
    XCTAssertNotEqual(built, chosen, "the point of this test is that these are different values")
    let change = RecordingsFolder.accessChange(from: chosen, to: built)
    XCTAssertNil(change.start)
    XCTAssertNil(change.stop)
  }
}
