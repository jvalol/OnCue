---
title: Stay awake while the schedule is on
status: shipped
created: 2026-09-23
commits: 1a2d34c (approval), 16b0681 (implementation), fce1022 (built state, manual checks), 9cab2db (the storyboard catalog kept out of Xcode's sync, found on the way), 70aa3e8 (released in 4.12)
---

## Problem
OnCue holds off idle sleep only while armed. With a schedule on, the assertion is released at
each window's end, the Mac sleeps on its own energy settings between windows, and a sleeping Mac
runs no timers: the next window's start passes unnoticed. Nothing in OnCue can wake it, since
scheduling a wake needs root. The wake check from 0038 catches up when something else wakes the
Mac, but a camera meant to arm at nine arms whenever somebody next touches the keyboard. The help
says the schedule needs OnCue open and that OnCue keeps the Mac awake while armed, which is true
and hides the gap: a Mac that sleeps between windows doesn't get the next one.

## Non-goals
- Waking a sleeping Mac. Not possible from a sandboxed app; the fix is not to let it sleep.
- Closing the lid. That stops OnCue regardless (0026 says so in the popover), and still will.
- Holding the assertion for a schedule with no windows, or when the schedule is off. Nothing
  is coming, so nothing to stay awake for.
- Display sleep. The assertion is idle-system-sleep only, as now; the screen may still go dark.

## Behaviour (acceptance criteria)
- [x] With the schedule on and at least one window, OnCue keeps the Mac from idle sleep whether or
      not it's armed. Unit test on `isKeepingAwake` across schedule on/off with and without
      windows, armed and unarmed.
- [x] With the schedule off, or on with no windows, keep-awake follows arming exactly as today.
      Existing unit tests unchanged.
- [x] A manual disarm during a window does not release the assertion while the schedule is on:
      the next window still has to arm. Unit test.
- [x] Activity Monitor's reason names why: "armed" while armed, the schedule while waiting for a
      window. Unit test on the reason chosen; the string itself is copy.
- [x] Unarmed with the schedule on, the popover's state line names the next window's start
      ("Unarmed until 9:00 tomorrow", with 0038's time-and-day wording), so the awake Mac has a
      visible reason. Unit test on `armedStateDescription` with a next start today, tomorrow and
      on a later weekday; and unchanged "Unarmed" with the schedule off or no window ahead.
- [x] The settings note under the schedule says the Mac stays awake the whole time the schedule
      is on, days without a window included. Manual check.
- [x] Across a real gap: a window ending, the Mac left alone past its sleep timeout, the next
      window arming on time. Manual check on this Mac with a short energy-saver timeout.
- [x] German for the new strings, and `LocalizationTests` green. Unit test (the invariant).
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
**One condition.** `RecordingManager.updateKeepAwake` decides from `armedState` alone. It gains a
second reason: `scheduleEnabled && !schedule.windows.isEmpty`. The assertion is the same
`.userInitiated` activity; which of the two reasons starts it only changes the string Activity
Monitor shows, so the activity is restarted when the reason changes (armed within a schedule,
schedule with no arming), not merely kept. `scheduleMayHaveChanged` already runs on every
schedule edit and calls `updateKeepAwake` after; `disarm()` keeps calling it, and with the
schedule on the answer stays yes.

**Why not "only near the next window".** The Mac has to be awake to notice the next window is
near, which is the same hole one step earlier. Awake for the whole time the schedule is on is the
only shape that works without root.

**The whole time, not near the next window.** A rule that releases the assertion when the next
start is far off (a weekday schedule over the weekend) lets the Mac sleep, and a sleeping Mac
can't notice the next start coming: Monday's window is missed unless someone wakes it first. So
the assertion is held for as long as the schedule is on with at least one window, including days
with nothing in them. Not a setting: a "let it sleep on off days" option is a camera that isn't
watching on Monday, chosen weeks earlier and forgotten, and the app's rule is reliability
unattended over features.

**Saying so.** Between windows the state line reads "Unarmed until <next start>", using
`describe(end:now:calendar:)` from 0038 for the time and day, next to the existing "Armed on
schedule until <end>". That's the reason the Mac isn't sleeping, in the place the user already
looks; no new notice on the notice row, which is for things that are wrong. `Schedule` gains
`nextStart(after:calendar:)`, the mirror of the window-end lookup, with tests.

**Cost.** A Mac that would have slept between windows idles with the display off instead, all
week for a weekday schedule. A scheduled camera is plugged in; on battery this is the same cost
arming already has, and the note says so.

**Copy.** The new Activity Monitor reason, and the schedule note's added sentence. Both go
through the catalogs with German (0043's invariant fails until they do).

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [x] On this Mac: energy saver set to sleep after one minute, a window ending, five minutes
      alone, the next window arming on the minute

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

Copy to convey: the Activity Monitor reason while waiting for a window (that OnCue is holding the
Mac awake for its schedule); the state line "Unarmed until <next start>"; one sentence in the
schedule note saying the Mac stays awake the whole time the schedule is on, days without a
window included; the help's schedule section saying the same and why.

## Tasks
- [x] `updateKeepAwake` with the schedule as a second reason, and the reason string per cause
- [x] Tests: schedule on/off, windows/none, armed/unarmed, manual disarm inside a window
- [x] `Schedule.nextStart` with tests; the state line "Unarmed until …" (marked copy)
- [x] Settings note and help section (marked copy), German for the new strings (marked copy)
- [x] The manual check across a real sleep timeout

## Verification
- **Built (2026-09-23):** `ScheduleWindow.nextStart(after:calendar:)` and `Schedule.nextStart`
  (earliest start within the coming week, nil when nothing is coming). `RecordingManager` keeps
  the assertion for a second reason, `KeepAwakeReason.schedule`, decided by a pure
  `keepAwakeReason(state:scheduleEnabled:nextStart:)`; the activity is restarted when the reason
  changes so Activity Monitor's text is right; `updateKeepAwake` runs at init, on every schedule
  change and on every arm-state change as before. `scheduleGeneration` bumps on schedule edits and
  each minute's look while unarmed, and is a dependent key path of the state line, so "Unarmed
  until <next start>" follows the clock. Fourteen new tests: six on `nextStart` (later today,
  inside a window, over a weekend, an overnight window, nothing coming, earliest across windows),
  eight on the manager (awake between windows, armed wins as the reason, manual disarm keeps it,
  schedule off releases it, nothing coming releases it, the reason rule, the state line naming
  tomorrow and Monday and today, plain "Unarmed" with the schedule off). Clean build, 326 tests.
- **Found on the way:** `RecordingManagerTests` built its manager on the app's real defaults, so
  the schedule on this Mac leaked into "Unarmed". It has its own suite now, like the schedule
  tests.
- **Checked on this Mac (Jake, 2026-09-23):** the state line and the note on screen, and the
  real gap: a window ending, the Mac left past its sleep timeout, the next window arming on the
  minute. Markers read and struck; `scripts/check` passes. Manual checks all good.

## Open questions
1. Resolved (Jake, 2026-09-23): the whole time the schedule is on with at least one window, no
   "near the next window" rule and no setting. The 24-hour idea was withdrawn after the arithmetic:
   a Mac released on Friday sleeps through the moment it would have picked the assertion up, and
   Monday's window is missed. Reliability unattended over a weekend of idle power.
2. Resolved (Jake, 2026-09-23): said through the state line, "Unarmed until <next start>", not a
   notice. The notice row is for things that are wrong; this is the schedule working, and the
   state line already carries the armed half of it.

## Closure
Shipped in 4.12 (2026-09-23), direct and tap, build 892 uploaded to App Store Connect by the
release script's store section.
