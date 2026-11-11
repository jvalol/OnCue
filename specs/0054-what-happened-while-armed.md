---
title: Say what happened while OnCue was armed, and show it
status: shipped
created: 2026-09-26
commits: 1b48ef1 (approval), eba3fcb and 2cdd071 (implementation, with the 0051 follow-ups), a93fcd8 (built state, manual checks), a286baf and ed67abf (released in 4.16)
---

## Problem
Coming home is the moment OnCue is for, and it's the moment it says nothing. The popover shows
the state; Show Recordings opens the folder at the newest file, which is the end of the story;
the folder holds everything from every day. The question in that moment is narrower: what
happened while I was out? OnCue knows exactly when that was, it armed and disarmed at both
ends, and every recording in between is its own file with a timestamp and, since 0053, a still.
It has the story and no way to tell it.

## Non-goals
- No time-lapse, no stitched movie, no contact-sheet image. The stills in Finder's gallery view
  are the sequence; this spec gets you to them. A rendered summary is a later spec if people go
  looking.
- No history of stretches. The last completed one is the one that matters; the folder keeps the
  rest.
- No new window. The popover and Finder do the showing.

## Behaviour (acceptance criteria)
- [x] A stretch is one armed period: from an arm, by any route (button, launch, schedule window,
      Focus, recovery after a crash), to its disarm, by any route (button, schedule end, Focus
      end, quit). Unit test on the state machine writing one stretch per period.
- [x] What happened in a stretch is OnCue's own recordings whose footage starts inside it, pre-roll
      allowed for at the start, stills included with their movies. Unit test on the pure rule
      over a list of files.
- [x] After a disarm, the popover says what the stretch held: how long OnCue was armed, how many
      events, and the time of the first and the last. One event says its one time. With none, the
      line says it was armed that long and nothing was recorded. Unit test on the text, plurals
      and German included; manual check.
- [x] An event is the files whose names carry timestamps within two seconds of each other, so
      two cameras' files from one trigger count once. Unit test on the grouping.
- [x] A stretch that had no event and lasted under ten minutes is not written; the line before
      it stays. Unit test on the rule at the boundary.
- [x] The line stays until the next stretch completes, so opening the popover an hour later, or
      after a relaunch, still answers. Arming again doesn't clear it. Unit test on persistence.
- [x] "Show What Happened" in the popover menu opens the recordings folder in Finder with the
      stretch's files selected, oldest first, stills included. It's enabled only while a stretch
      with recordings is remembered, and it's the same action from a line in the popover. Unit
      test on the menu validation and the URL list; manual check in Finder.
- [x] A stretch cut short by a crash (0045) ends at the last time OnCue was seen, so its
      recordings still count. Unit test.
- [x] Every string is under the marker with German; `LocalizationTests` green. Unit test.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- **`ArmedStretch`**, new, in `Managers/Helpers`, in both targets, AppKit-free. A value of
  `from` and `to`; `read(from:)`/`write(to:)` on defaults under one key; `files(in:from:to:
  preRoll:)` picks recordings by `FileOutputManager.recordingDate`, and pairs stills through
  a two-second timestamp tolerance (looser than 0053's `eventKey`, which keeps the device
  names because the window deletes files, where this counts what happened); `summary(...)`
  builds the line. `minimumEmptyStretch` is ten minutes. `RecordingManager` records `from` when the
  state leaves unarmed and writes the stretch when it returns there. 0045's `ArmedRecord`
  already tracks the arm time and the last-seen minute; a recovery that finds a record writes
  the stretch it implies before re-arming, so a crash closes the story at the last minute seen.
- **The popover line.** 0033's line under the state already talks about recordings, in the
  last day. While unarmed and a stretch is remembered, that line reads the stretch instead:
  it's the same slot answering a better question. While armed it says what it says today.
  The line is a button when there's something to show, the same action as the menu item.
- **Finder.** `NSWorkspace.activateFileViewerSelecting(_:)` with the stretch's URLs, oldest
  first. Finder selects them all and scrolls to the first; gallery view then steps through
  the stills in order. With the folder missing (a drive unplugged) the menu item is disabled,
  like Show Recordings' fallback.
- **Rejected:** a notification on disarm ("7 recordings while you were out"), because disarming
  is something you just did in the popover, which is open; a stretch per schedule window kept
  as a list, because the last one is the question and the folder keeps the rest; counting from
  the still files rather than the movies, because a movie can exist without a still (audio
  only) and the movie is the recording.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

## Tasks
- [x] `ArmedStretch`: value, defaults, the file rule, the summary, with tests
- [x] `RecordingManager` writes the stretch on every route out of armed, and from a recovery
- [x] The popover line while unarmed, as a button when there's something to show
- [x] "Show What Happened" in the popover menu, validated
- [x] Catalog entries with German
- [x] Help page paragraph (marked, in `site/help`); the changelog entry comes with the release

## Verification
- **Built (2026-09-26):** `ArmedStretch` (`Managers/Helpers`, both targets): the value and its
  defaults keys, `armedSince` written beside 0045's record in `refreshArmedRecordOnArm` (once per
  period; a defaults write inside the state change would trip the auto-disarm observer, which is
  how the interruption tests found it), `events(in:stretch:preRoll:)` grouping by a two-second
  tolerance with a stable sort, `isWorthKeeping` at ten minutes, `summary` with three lines and
  `durationText` at two abbreviated units. `RecordingManager` closes the stretch in the state
  setter on every route to unarmed (a test's cleanup disarm suppressed), on a normal quit while
  armed, and from a recovery at the last minute seen; `whatHappened()` re-reads the folder;
  `stretchGeneration` tells the popover. The popover's cost line carries the stretch while
  unarmed, in the link colour and clickable when there are files; "Show What Happened" in the
  menu is enabled on the same condition, and both select the files in Finder oldest first.
  Sixteen tests: defaults round trips, the stretch window with pre-roll, two cameras and stills
  as one event, the tolerance boundary, worth-keeping at the boundary, durations, the three
  lines, the menu rule, and on the manager: a long empty stretch kept, a short one leaving the
  previous, a quit closing it, a recovery closing it at the last minute seen and opening the
  next. Clean build, 403 tests, no warnings.
- **Found on the first check (Jake, 2026-09-26):** the line showed the I-beam on hover, since a
  text field is selectable. It's now non-selectable and shows the pointing hand while it's a
  button. Two 0051 follow-ups came out of the same session and ride with this: the popover's
  notice now follows a change to Open at Login made in Settings while the popover is open, and
  the grey note under the schedule drops "turn on Open OnCue at Login" once it's on.
- **Checked on this Mac (Jake, 2026-09-26 07:32):** the line after a disarm ("Armed for 2m: 5
  recordings between 07:09 and 07:11"), the click and the menu item opening Finder with the
  stretch's files selected, a short empty stretch leaving the line alone, the line after a
  relaunch. Copy read and edited; markers struck. `scripts/check` green.

## Open questions
1. Resolved (Jake, 2026-09-26): 0033's line under the state carries the stretch while OnCue is
   unarmed and a stretch is remembered, and is the button; while armed it says what it says
   today. The popover doesn't grow a line for a few hours a day.
2. Resolved (Jake, 2026-09-26): the line is written when the stretch had a recording, or lasted
   at least ten minutes. A shorter empty stretch, the kind a setup toggle makes, leaves the
   previous line in place. The threshold is a constant, not a setting.
3. Resolved (Jake, 2026-09-26): the count is events, not files. Files whose names carry
   timestamps within two seconds of each other are one event, which is what two cameras make
   of one trigger; every file of the stretch, stills included, is selected in Finder.

## Closure
Shipped in 4.16 (2026-09-26), direct download and the tap (cask `eb1471d`, `scripts/check-tap`
green), build 911 uploaded to App Store Connect by the release run; the store version follows
once the versions ahead of it clear review.
