---
title: Record a test
status: shipped
created: 2026-09-23
commits: d3f578f (approval), 182401c (implementation), 4d4119f (built state, manual checks), bab71b1 (the audio-only fix, under 0050), 6a9bc4a and b105605 (released in 4.13)
---

## Problem
The only way to find out whether a setup records is to arm, wave at the camera, wait for the
timeout, and go and look in the folder. Everything that can be wrong with a setup shows up only
then: camera permission, the device chosen, the microphone, the folder being there and writable,
the disk budget, pre-roll, the timeout, naming, the second camera. The meters prove the
thresholds; nothing proves the rest of the chain until real motion does, which for a camera
pointed at an empty room can be hours after the person has walked away believing it works. App
Review had the same problem from the other side: asked what the Movies entitlement was for, the
honest answer was "make it record", and there was no button for that.

## Non-goals
- A self-test of thresholds. The meters and the preview are that.
- A diagnostic report. The test is the ordinary recording path, started by hand; what it finds
  wrong is said the way any recording says it (0027, 0029).
- Anything in a shipped build that makes OnCue fail on purpose (0035, abandoned, and Jake's
  decision there stands).
- A shorter or different file. A test is a recording, named and kept like every other.

## Behaviour (acceptance criteria)
- [x] "Record a test" in the popover's gear menu, enabled whenever Arm would be (something can
      fire) or OnCue is already armed, and disabled while a recording is in progress. Unit test
      on the enabling rule.
- [x] From unarmed: OnCue counts down for as long as the pre-roll setting needs and never less
      than Arm's five seconds (the ring fills meanwhile), records on every running camera the way
      a trigger does, ends the recording after the normal timeout, and disarms again. Unit test on
      the countdown rule and on the sequence in the manager with a fake clock; manual check on
      this Mac, in a Release build, since Debug builds skip countdowns (0002, 0018).
- [x] From armed: no countdown; the recording starts at once and OnCue stays armed afterwards.
      Unit test; manual check.
- [x] Anything a trigger's recording would report, a test's does too: a failure (0027), no room
      (0029), a deletion under the size limit. A failed test does not clear its own notice when
      it disarms. Unit test with a failing recorder.
- [x] When the test's file finishes, the newest recording is revealed in Finder, the way Show
      Recordings does. Manual check.
- [x] The state line reads "Recording" during the test, as it does for any recording. No new
      state. Existing unit tests unchanged.
- [x] German for the new strings; `LocalizationTests` green. Unit test (the invariant).
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
**The same path, started by hand.** `CaptureManager.activityDetected` is what a trigger calls:
start recording on every running camera and schedule the stop after the timeout. A test calls
the same thing. The only new machinery is the arming around it when OnCue was unarmed, and the
cleanup after.

**In the manager.** `RecordingManager.recordTest()`: if unarmed, remember that, arm with a
countdown of `max(5, preRollSeconds)` (the countdown fills the pre-roll ring, which is empty while
capture isn't running, 0023; five is Arm's countdown, and a longer pre-roll needs longer to prove
itself) and fire the test when the countdown reaches armed; if armed, fire it now.
"Fire" is a callback the capture manager registers, the way `onArmedAtLaunch` is, that calls
`activityDetected`. When the recording ends (`recordingDidFinish` bringing the state back to
armed), disarm if the test armed it. `isRecordingTest` is true from the call to the cleanup so
the menu item can disable and the cleanup knows what it's cleaning.

**A failed test stays on the line.** `disarm()` clears the failure and deletion notices. The
test's cleanup disarms through a variant that leaves them: the person pressed the button to
learn exactly this. The gap and sleep notices are cleared as usual; nothing in a test makes them.

**Reveal.** `recordingDidFinish` for a test's file calls the same reveal Show Recordings uses,
once per test (the first file to finish with two cameras). A failed file reveals nothing; the
notice says why.

**The countdown is visible.** From unarmed, the popover counts down as it does for Arm, and
the 0018 notification isn't posted: `onArmedAtLaunch` fires only for login, the schedule and
crash recovery, the armings nobody watched, and a test calls `startArming` directly, as Arm
does. In a Debug build `startArming` skips the countdown (0002), so the pre-roll part of a test
can only be seen in a Release build.

**It counts.** The file is a recording with a recording's name, so the trigger-cost line counts
it. Excluding it would need a mark the name parser (0017) and the size-limit trim would both have
to learn, for a one-recording error in a count that only means anything above three.

**Copy.** The menu item. Nothing else is new on screen.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [x] On this Mac: from unarmed, a test that counts down, records, disarms and reveals the file;
      from armed, one that records at once and stays armed; with the folder on an ejected drive,
      one that fails and says so

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

Copy to convey: the menu item, that it records a test; a help sentence saying what a test
records and that it's a normal recording.

## Tasks
- [x] `recordTest()`, the fire callback, the cleanup that keeps notices, with tests
- [x] The menu item and its enabling (marked copy)
- [x] The reveal on finish
- [x] Help sentence (marked copy), German (marked copy)
- [x] The manual checks

## Verification
- **Built (2026-09-23):** `RecordingManager.recordTest()` with the pure `canRecordTest(state:canArm:)`
  and `testCountdown(preRollSeconds:)`; `onTestRecordingWanted` (the app delegate points it at
  `CaptureManager.recordTestNow()`, the trigger's own start, run synchronously so the manager can
  see whether a recording began) and `onTestRecordingFinished` (pointed at Finder's reveal).
  `countdown()` fires the test when it reaches armed; `recordingDidFinish` counts the test's files
  down and reveals the first that finished cleanly; `finishTest()` disarms through
  `disarm(keepingNotices:)`, which leaves the failure and deletion notices standing. A manual
  disarm mid-test ends the test and lets its files finish as ordinary ones. "Record a Test" in the
  popover menu after Show Recordings, enabled through `validateMenuItem` by the rule. Nine tests:
  the countdown rule, the offering rule, from armed (records at once, stays armed, reveals), from
  unarmed (counts down five, records, disarms, reveals), a longer pre-roll's longer countdown, a
  failed test keeping its notice through the cleanup and losing it on an ordinary disarm, a
  recording that never starts ending the test, a manual disarm mid-test, and a second press
  doing nothing. Clean build, 353 tests.
- **Checked on this Mac (Jake, 2026-09-23):** the menu item; from unarmed, a test that
  records, disarms and reveals the file; from armed, one that records at once and stays armed;
  a failing one that says so. Markers read and struck (the catalog's two by Claude at Jake's
  request, since Xcode's editor wouldn't). An Xcode build between the strike and the gate had
  re-extracted the key without its German; merged back into one entry. `scripts/check` passes.
  Manual checks all good.

## Found after shipping the build (2026-09-23)
From unarmed with the popover closed (a Shortcuts action, 0050), the test fired the moment the
countdown reached armed, before the cameras had produced a frame, and the recorders opened
without a video format: two audio-only files. The manual checks here never saw it because the
popover being open keeps capture running. Fixed under 0050: capture waits for a frame from every
running camera before starting the test's recording, and the manager gives up after fifteen
seconds if none comes.

## Open questions
1. Resolved (Jake, 2026-09-23): a test counts in the trigger-cost line. It's a recording; a mark
   to exclude it is machinery for a one-recording error that's gone by tomorrow.
2. Resolved (Jake, 2026-09-23): no "arming itself" notification. That callback fires only for
   arming nobody asked for at that moment (login, schedule, crash recovery); a test, like Arm,
   is started from the open popover and doesn't fire it.
3. Resolved (Jake, 2026-09-23): from unarmed, count down for the pre-roll setting and never less
   than Arm's five seconds. Five matches Arm for the default setup; a longer pre-roll gets the
   time it needs, since proving the setting is what the test is for. The fifteen-second launch
   countdown is for arming nobody is watching and doesn't apply.

## Closure
Shipped in 4.13 (2026-09-23), direct and tap, build 900 uploaded to App Store Connect by the
release script's store section; the store version follows when 4.12 clears review.
