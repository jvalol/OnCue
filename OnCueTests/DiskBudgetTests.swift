//
//  DiskBudgetTests.swift
//  OnCueTests
//
//  Created by Jake Van Alstyne on 9/20/26.
//  Copyright © 2026 Jake Van Alstyne. All rights reserved.
//

import XCTest

class DiskBudgetTests: XCTestCase {
  private let gb: Int64 = 1024 * 1024 * 1024

  private func recording(_ minute: Int, gb size: Double, name: String = "r") -> DiskBudget.Recording {
    DiskBudget.Recording(url: URL(fileURLWithPath: "/tmp/\(name)\(minute).mov"),
                         started: Date(timeIntervalSince1970: TimeInterval(minute) * 60),
                         bytes: Int64(size * Double(gb)))
  }

  // MARK: - Stopping before the disk is full

  func testThereIsRoomWhenTheHeadroomIsIntact() {
    XCTAssertTrue(DiskBudget.hasRoomToRecord(freeBytes: 50 * gb))
    XCTAssertTrue(DiskBudget.hasRoomToRecord(freeBytes: DiskBudget.headroomBytes))
  }

  func testThereIsNoRoomBelowTheHeadroom() {
    XCTAssertFalse(DiskBudget.hasRoomToRecord(freeBytes: DiskBudget.headroomBytes - 1))
    XCTAssertFalse(DiskBudget.hasRoomToRecord(freeBytes: 0))
  }

  // MARK: - Reading the limit out of a preference

  func testTheWindowIsOffAtZeroOrBelow() {
    XCTAssertNil(DiskBudget.limitBytes(gigabytes: 0))
    XCTAssertNil(DiskBudget.limitBytes(gigabytes: -5))
  }

  func testALimitInGigabytes() {
    XCTAssertEqual(DiskBudget.limitBytes(gigabytes: 1), gb)
    XCTAssertEqual(DiskBudget.limitBytes(gigabytes: 250), 250 * gb)
    XCTAssertEqual(DiskBudget.limitBytes(gigabytes: DiskBudget.maximumLimitGB),
                   Int64(DiskBudget.maximumLimitGB) * gb)
  }

  /// The limit is a preference, and a preference is a file any process running as the user can
  /// write. Settings will not accept a number this big, but nothing stops one being written
  /// straight into defaults, and Int64 multiplication traps on overflow. A camera that dies the
  /// next time a recording finishes is a worse outcome than a limit that got clamped.
  func testALimitTooBigToMultiplyIsClampedRatherThanCrashing() {
    XCTAssertEqual(DiskBudget.limitBytes(gigabytes: Int.max), Int64(DiskBudget.maximumLimitGB) * gb)
    XCTAssertEqual(DiskBudget.limitBytes(gigabytes: DiskBudget.maximumLimitGB + 1),
                   Int64(DiskBudget.maximumLimitGB) * gb)
  }

  // MARK: - Rolling a recording that is over the limit on its own (spec 0031)

  /// Deleting can't help once the growing file alone is over the limit, so the recording rolls and
  /// the file that closes becomes deletable like any other.
  func testARecordingOverTheLimitOnItsOwnRolls() {
    XCTAssertTrue(DiskBudget.shouldRoll(inProgressBytes: 21 * gb, limitBytes: 20 * gb))
    XCTAssertFalse(DiskBudget.shouldRoll(inProgressBytes: 20 * gb, limitBytes: 20 * gb))
    XCTAssertFalse(DiskBudget.shouldRoll(inProgressBytes: 1 * gb, limitBytes: 20 * gb))
  }

  /// With the window off nothing rolls, however long the recording runs. Someone who set no limit
  /// asked for no management, and the free space stop is what protects the disk for them.
  func testNothingRollsWithTheWindowOff() {
    XCTAssertFalse(DiskBudget.shouldRoll(inProgressBytes: 500 * gb, limitBytes: nil))
    XCTAssertFalse(DiskBudget.shouldRoll(inProgressBytes: 500 * gb, limitBytes: 0))
  }

  /// Two cameras means two files open at once, and the limit is on what they add up to.
  func testBothCamerasCountTowardsRolling() {
    XCTAssertTrue(DiskBudget.shouldRoll(inProgressBytes: 11 * gb + 11 * gb, limitBytes: 20 * gb))
    XCTAssertFalse(DiskBudget.shouldRoll(inProgressBytes: 9 * gb + 9 * gb, limitBytes: 20 * gb))
  }

  /// The decision doesn't depend on what else is in the folder, so it can't depend on whether
  /// trimming has already run this tick.
  func testRollingIgnoresWhateverElseIsInTheFolder() {
    let overOnItsOwn = DiskBudget.shouldRoll(inProgressBytes: 25 * gb, limitBytes: 20 * gb)
    XCTAssertTrue(overOnItsOwn)
    // Same call, same answer, whatever toDelete would or wouldn't have taken first.
    XCTAssertEqual(DiskBudget.shouldRoll(inProgressBytes: 25 * gb, limitBytes: 20 * gb), overOnItsOwn)
  }

  // MARK: - The rolling window

  /// Off by default: without a limit nothing is ever deleted, however much has piled up.
  func testNothingIsDeletedWithoutALimit() {
    let recordings = [recording(1, gb: 10), recording(2, gb: 10), recording(3, gb: 10)]
    XCTAssertEqual(DiskBudget.toDelete(recordings, limitBytes: nil), [])
    XCTAssertEqual(DiskBudget.toDelete(recordings, limitBytes: 0), [])
  }

  func testNothingIsDeletedUnderTheLimit() {
    let recordings = [recording(1, gb: 5), recording(2, gb: 5)]
    XCTAssertEqual(DiskBudget.toDelete(recordings, limitBytes: 20 * gb), [])
  }

  func testTheOldestGoFirst() {
    let oldest = recording(1, gb: 5), middle = recording(2, gb: 5), newest = recording(3, gb: 5)
    // 15 GB against a 10 GB limit: the oldest alone brings it under.
    XCTAssertEqual(DiskBudget.toDelete([newest, oldest, middle], limitBytes: 10 * gb), [oldest])
  }

  func testItDeletesOnlyAsMuchAsItNeedsTo() {
    let recordings = (1...5).map { recording($0, gb: 4) }
    // 20 GB against 9 GB: three have to go, the fourth would be wasteful.
    let deleting = DiskBudget.toDelete(recordings, limitBytes: 9 * gb)
    XCTAssertEqual(deleting.count, 3)
    XCTAssertEqual(deleting.map { $0.url }, recordings.prefix(3).map { $0.url })
  }

  /// Deleting the file under an open writer would lose the recording OnCue is making right now.
  func testTheRecordingInProgressIsNeverDeleted() {
    let inProgress = recording(1, gb: 30)
    let others = [recording(2, gb: 5), recording(3, gb: 5)]
    let deleting = DiskBudget.toDelete([inProgress] + others, limitBytes: 10 * gb,
                                       keeping: [inProgress.url.path])
    XCTAssertFalse(deleting.contains(inProgress))
  }

  /// Two cameras means two files open at once, so this was never one recording to protect.
  func testBothRecordingsInProgressAreKeptWithTwoCameras() {
    let first = recording(1, gb: 20), second = recording(2, gb: 20)
    let old = [recording(3, gb: 5), recording(4, gb: 5)]
    let deleting = DiskBudget.toDelete([first, second] + old, limitBytes: 1 * gb,
                                       keeping: [first.url.path, second.url.path])
    XCTAssertFalse(deleting.contains(first))
    XCTAssertFalse(deleting.contains(second))
    XCTAssertEqual(deleting, old)
  }

  /// The guard matches on where a file is, not on how its URL was built. Comparing URL values
  /// silently matched nothing: the recorder's URL and a directory scan's URL for the same file
  /// are not equal, so the recording in progress was offered up for deletion like any other.
  func testTheGuardMatchesTheFileHoweverTheURLWasBuilt() {
    let folder = URL(fileURLWithPath: "/tmp", isDirectory: true)
    let scanned = DiskBudget.Recording(url: folder.appendingPathComponent("r1.mov"),
                                       started: Date(timeIntervalSince1970: 60), bytes: 30 * gb)
    let asTheRecorderBuiltIt = URL(fileURLWithPath: "r1.mov", relativeTo: folder)
    XCTAssertNotEqual(scanned.url, asTheRecorderBuiltIt, "the point of this test is that these differ")

    let others = [recording(2, gb: 5), recording(3, gb: 5)]
    let deleting = DiskBudget.toDelete([scanned] + others, limitBytes: 10 * gb,
                                       keeping: [asTheRecorderBuiltIt.standardizedFileURL.path])
    XCTAssertFalse(deleting.contains(scanned))
  }

  /// If the only thing over the limit is the recording in progress, there's nothing to do but
  /// carry on: deleting everything else wouldn't help and would destroy footage for nothing.
  func testWhenOnlyTheRecordingInProgressIsOverTheLimit() {
    let inProgress = recording(1, gb: 30)
    XCTAssertEqual(DiskBudget.toDelete([inProgress], limitBytes: 10 * gb, keeping: [inProgress.url.path]), [])
  }

  // MARK: - A movie and its still are one event (spec 0053)

  private func still(_ minute: Int, mb size: Double, name: String = "r") -> DiskBudget.Recording {
    DiskBudget.Recording(url: URL(fileURLWithPath: "/tmp/\(name)\(minute).jpg"),
                         started: Date(timeIntervalSince1970: TimeInterval(minute) * 60),
                         bytes: Int64(size * 1024 * 1024))
  }

  func testAStillGoesWithItsMovie() {
    let oldMovie = recording(1, gb: 5), oldStill = still(1, mb: 0.3)
    let newMovie = recording(2, gb: 5), newStill = still(2, mb: 0.3)
    // The oldest movie alone brings 10.0006 GB under 6 GB; its still goes with it anyway.
    let deleting = DiskBudget.toDelete([newStill, oldStill, newMovie, oldMovie], limitBytes: 6 * gb)
    XCTAssertEqual(deleting, [oldMovie, oldStill])
  }

  func testAStillIsNeverDeletedOnItsOwn() {
    // Two events, 5 GB each plus a still, against a limit the oldest still would satisfy alone
    // if stills were weighed as files: the movie goes with it because they're one event.
    let oldMovie = recording(1, gb: 5), oldStill = still(1, mb: 0.3)
    let newMovie = recording(2, gb: 5), newStill = still(2, mb: 0.3)
    let limit = Int64(Double(10 * gb) + 0.4 * 1024 * 1024)
    let deleting = DiskBudget.toDelete([oldStill, newStill, oldMovie, newMovie], limitBytes: limit)
    XCTAssertEqual(deleting, [oldMovie, oldStill])
  }

  func testTheStillOfTheRecordingInProgressIsKeptToo() {
    let inProgress = recording(1, gb: 30), itsStill = still(1, mb: 0.3)
    let old = recording(2, gb: 5)
    let deleting = DiskBudget.toDelete([inProgress, itsStill, old], limitBytes: 10 * gb,
                                       keeping: [inProgress.url.path])
    XCTAssertEqual(deleting, [old])
  }

  func testAMovieRenamedForMissingSecondsKeepsItsStill() {
    let movie = DiskBudget.Recording(url: URL(fileURLWithPath: "/tmp/2026-09-25 17.40.12 - 28s missing.mov"),
                                     started: Date(timeIntervalSince1970: 60), bytes: 5 * gb)
    let itsStill = DiskBudget.Recording(url: URL(fileURLWithPath: "/tmp/2026-09-25 17.40.12.jpg"),
                                        started: Date(timeIntervalSince1970: 60), bytes: 1000)
    XCTAssertEqual(DiskBudget.eventKey(for: movie.url), DiskBudget.eventKey(for: itsStill.url))
    let newer = recording(2, gb: 5)
    XCTAssertEqual(DiskBudget.toDelete([newer, itsStill, movie], limitBytes: 6 * gb), [movie, itsStill])
  }

  func testStillsCountTowardTheLimit() {
    let movie = recording(1, gb: 1), itsStill = still(1, mb: 0.3)
    // Exactly 1 GB of movie against a 1 GB limit is under; the still tips it over.
    XCTAssertEqual(DiskBudget.toDelete([movie], limitBytes: 1 * gb), [])
    XCTAssertEqual(DiskBudget.toDelete([movie, itsStill], limitBytes: 1 * gb), [movie, itsStill])
  }

  func testAnEmptyFolderHasNothingToDelete() {
    XCTAssertEqual(DiskBudget.toDelete([], limitBytes: 10 * gb), [])
  }
}
