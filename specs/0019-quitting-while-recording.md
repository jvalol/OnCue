---
title: Say what's happening when quitting during a recording
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-19
commits: a0be430 (spec), f3551cc (implementation)
---

## Problem
Quitting OnCue while it's recording now waits for the files to finish writing, because a file cut
short has no index and won't open. The wait is silent: OnCue just doesn't quit for up to five
seconds, with nothing on screen saying why and no way to say "quit anyway".

## Non-goals
- Changing how files are written, or the two-second index flush that already makes an interrupted
  file playable.
- Anything about quitting while armed but not recording; that quits straight away, as now.

## Behaviour (acceptance criteria)
- [x] Quitting while recording shows a message saying OnCue is finishing its recording. Manual
      check.
- [x] The message offers to quit straight away without waiting, and doing so leaves a file that
      still opens, thanks to the index flush. Manual check.
- [x] It can also be cancelled, leaving OnCue running and still recording. Manual check.
- [x] Once the files finish, OnCue quits on its own and the message goes away. Manual check.
- [x] Quitting when nothing is recording still quits immediately. Unit test on the decision.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- `applicationShouldTerminate` already returns `.terminateLater` while recording. It also shows an
  `NSAlert`, in front, with buttons to quit now or keep running, and dismisses it when the files
  finish.
- Quitting now means replying to the termination at once; the files stay as they are, playable up
  to the last flush.
- No time limit: with the message in front, OnCue waits until the files finish or the user chooses.
- The decision (quit now, or wait and say so) is a pure function of whether a recording is in
  progress, so it's unit-tested; the alert itself is a manual check.
- The message and its buttons are copy: drafts carry `[COPY - Jake]`.

- **Built (2026-09-19):** `RecordingManager.waitsBeforeQuitting(isRecording:)` is the decision;
  `AppDelegate` runs the alert modally while the files finish and dismisses it from
  `onRecordingsFinished`. The index flush that makes Quit Now safe landed with the bug fix before
  this spec.

## Gates
- [x] `scripts/check` passes
- [x] Manual checks: quit while recording, quit anyway, cancel, and quit with nothing recording

## Tasks
- [x] The alert, its buttons, and dismissing it when the files finish
- [x] Manual checks, Verification filled in

## Verification
- `RecordingInterruptionTests` adds the quit decision and "every file has finished". 102 tests pass
  on a clean build with no warnings (`scripts/check`).
- Jake's manual checks (2026-09-19): it works as designed.

## Open questions
Resolved by Jake, 2026-09-19: wait indefinitely, since the message explains the wait and offers a
way out.
