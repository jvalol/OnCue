---
title: Say when OnCue quit unexpectedly, and go back to watching
status: shipped
created: 2026-09-23
commits: 2091155 (approval), 7a5b335 (implementation), 2dbf416 (built state, manual checks), 6a9bc4a and b105605 (released in 4.13)
---

## Problem
If OnCue dies while armed (a crash, a force quit, a power cut), nothing is watching and nothing
ever says so. The next launch starts unarmed unless arm-at-login is on, and even then the hours
between the death and the login are a gap nobody is told about. Every other way of not watching
has a notice: sleep (0008), motion detection stopping (0030), a recording failing (0027). This is
the last silent one, and it's the one a security camera can least afford: the user believes it
was watching, and it wasn't.

## Non-goals
- Relaunching OnCue after a crash. That needs a launchd agent with KeepAlive, which changes how
  the app is started and how the login item works (0018). Worth its own spec if this one shows
  crashes happen; this one makes the gap visible and ends it at the next launch.
- Diagnosing the crash. macOS keeps the report; OnCue says when it happened, not why.
- Telling a force quit from a crash. Both leave the same trace and the same gap; a person who
  force-quit knows.

## Behaviour (acceptance criteria)
- [x] While armed, OnCue keeps a record of being armed, refreshed every minute. Disarming clears
      it, and so does a normal quit, including the quit that waits for a recording to finish
      (0019). Unit test on the record across arm, the minute look, disarm and the quit hook.
- [x] On launch, a record left from the previous run means that run ended without disarming. The
      popover then says OnCue quit unexpectedly at the recorded time and wasn't watching until
      now, and the notification the sleep gap already posts (0008) posts for this gap too. Unit
      test on the rule from a stale record; manual check by killing the process.
- [x] On that launch OnCue arms again, with the launch countdown and the arming notification
      (0018), whether or not arm-at-login is on: it was armed, and a crash isn't a decision to
      stop. If the schedule had armed it, it re-arms only if the launch is inside a window;
      otherwise the window has ended and the schedule's own rule applies. Unit test on the rule
      with and without the schedule.
- [x] A launch with no record does nothing new: the fresh-start notice (0037), arm-at-login and
      the schedule behave exactly as today. Existing unit tests unchanged.
- [x] The notice ranks with the other "happened" notices (0030's gap), below a recording failure
      and above the lid warning, and clears the way the gap notice clears. Unit test on the
      ranking.
- [x] German for the new strings; `LocalizationTests` green. Unit test (the invariant).
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
**The record.** `ArmedRecord` in `OnCue/Managers/Helpers/`, the shape of `FreshStart`: one
defaults key holding the last moment OnCue was known to be armed, plus whether the schedule armed
it. `RecordingManager` writes it when arming starts, rewrites it on each minute look
(`checkSchedule` already fires on the minute whether or not a schedule is on), and removes it in
`disarm()`. `AppDelegate.applicationWillTerminate` removes it too, so a normal quit while armed
leaves nothing behind; the 0019 wait ends in the same hook. A record found at launch is therefore
a run that ended without either.

**The launch rule.** Pure: `ArmedRecord.recovery(record:now:insideWindowNow:)` returns whether to
re-arm and the gap to report. Re-arm unless the record says the schedule armed it and the launch
is outside every window. `RecordingManager.deviceAvailabilityChanged`, the launch moment
arm-at-login and the schedule already use, runs it once before them: arming from here sets
`armedAtLaunch` so arm-at-login doesn't arm twice, and sets `armedBySchedule` when the record had
it, so the window's end still disarms.

**The gap.** Reported through the existing not-watching pair (`notWatchingFrom`,
`notWatchingUntil`), so the popover's observer and the 0008 notification need no new wiring. What
needs a new line is the notice itself: `PopoverNotice` gains `quitUnexpectedly(at:until:)`, ranked
with `wasNotWatching`, worded to say the app stopped rather than the Mac slept, because the
reader's next step differs (look at the crash report, not the lid).

**Accuracy.** The record is a minute old at most, so the gap's start is within a minute of the
death. Good enough to read; the spec doesn't claim the second.

**Cost.** One defaults write a minute while armed. Nothing while unarmed.

**Copy.** The popover line and the notification text for the unexpected quit, in English and
German.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [x] On this Mac: armed, `kill -9` from a terminal, relaunch, the notice naming the kill time,
      the notification, and OnCue arming itself again; then a normal quit while armed and a
      relaunch showing nothing

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

Copy to convey: that OnCue quit unexpectedly at a time and wasn't watching until it came back;
the notification saying the same and that nothing was recorded in between.

## Tasks
- [x] `ArmedRecord`: write on arm, refresh on the minute, clear on disarm and on quit, with tests
- [x] The launch rule, and its use from `deviceAvailabilityChanged`, with tests
- [x] `PopoverNotice.quitUnexpectedly` and its ranking, with tests; the popover line and the
      notification (marked copy), German (marked copy)
- [x] The manual check with `kill -9`

## Verification
- **Built (2026-09-23):** `ArmedRecord` (two defaults keys: last seen, by schedule; `read`,
  `write`, `clear`, and the pure `recovery(from:insideWindowNow:)`). `RecordingManager` writes it
  as arming starts, rewrites it from the minute look while armed, clears it in `disarm()` and in
  `noteNormalQuit()`, which `applicationWillTerminate` calls. `recoverFromUnexpectedQuit()` runs
  once, from the launch moment before arm-at-login: consumes the record, re-arms with the launch
  countdown and the arming notification (setting `armedAtLaunch` so arm-at-login stands down, and
  `armedBySchedule` when the record had it), and sets the `quitUnexpectedlyAt`/`Until` pair.
  `PopoverNotice.quitUnexpectedly(at:until:)`, shown armed or not, ranked by recency with the
  gap, the failure and the deletion. The popover observes the pair, shows the line (time alone
  today, date and time otherwise) and posts a notification. Fifteen new tests: the record round
  trip; the rule with no record, by hand, and by schedule inside and outside a window; in the
  manager, written on arm, refreshed by the minute look, not written unarmed, cleared by a normal
  quit, a launch after a death arming and reporting, independent of arm-at-login, once per
  launch, nothing with no record, and the two schedule cases; in the notice, shown armed or not
  and ranked. Clean build, 344 tests.
- **Found on the way:** writing the record touches defaults, and the defaults observer
  auto-disarms when nothing can fire. In the app nothing can be armed in that state; in the
  tests the manager had never been told a camera exists. `RecordingManagerTests` now declares
  one at setup, as the schedule tests do.
- **Checked on this Mac (Jake, 2026-09-23):** armed, `kill -9`, relaunch: the notice with the
  kill time, the notification, OnCue counting down and arming again; then a normal quit while
  armed and a relaunch showing nothing. Markers read and struck; `scripts/check` passes. Manual
  checks all good.

## Open questions
1. Resolved (Jake, 2026-09-23): re-arm on relaunch whatever the arm-at-login setting. A crash is
   the one ending nobody chose, so the recovery restores what was chosen; the countdown
   notification and the notice explain a relaunch days later, and Disarm is one click. With the
   schedule, only inside a window.
2. Resolved (Jake, 2026-09-23): its own line, naming the unexpected quit and when it came back.
   The gap line reads as sleep and hides the crash a second time; a user quoting "quit
   unexpectedly at 3am" is a bug report, "wasn't watching" is not.
3. Follow-up, not this spec: relaunch on crash through a launchd agent with KeepAlive. Only worth
   it if this spec's notice turns out to appear.

## Closure
Shipped in 4.13 (2026-09-23), direct and tap, build 900 uploaded to App Store Connect by the
release script's store section; the store version follows when 4.12 clears review.
