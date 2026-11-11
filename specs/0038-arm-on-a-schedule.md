---
title: Arm on a schedule
status: shipped
created: 2026-09-22
commits: 7bc0127 (approval), 33650b8 (implementation), d096bd1 and ec61698 and ddcd920 (follow-ups from the gate), 952b5ca (released in 4.9)
---

## Problem
OnCue arms when someone presses Arm, or once at launch if arm-at-login is on. Both need a person
or a restart. The common case for a security camera is neither: the same hours every day, the
house empty from nine to five, the shop closed overnight. Today that means arming by hand before
leaving and remembering to disarm on return, and a forgotten disarm means an evening of recordings
of the household, which is the failure that makes people stop using it.

Version 2 had scheduled recording; the rewrite dropped it, and the most detailed review on the
App Store lists it among the things that made the old app worth using daily. This brings it back
in the shape the current app has: arming, not recording. Nothing about what a recording is changes.

## Non-goals
- Recording continuously between two times. OnCue records when something happens; the schedule
  decides when it is watching, not when it is writing.
- Launching OnCue. A sandboxed app cannot schedule its own launch, so the schedule works only
  while OnCue is running. Open at login (0015) is the way to have it running; Settings says so
  next to the schedule.
- Overlapping windows meaning anything special. If two rows cover the same moment, OnCue is
  armed; the end of the last one to finish disarms it.
- Calendar integration, holidays, geofencing, or anything that decides "away" for the person.

## Behaviour (acceptance criteria)
- [x] Settings has a schedule: on or off, and a list of windows, each with the days of the week it
      applies to, a start time and an end time. Rows can be added and removed. Empty by default,
      and off. Manual check.
- [x] While the schedule is on and OnCue is running, it arms itself at the start time on a chosen
      day and disarms at the end time. Unit test on the rule; manual check with a two-minute window.
- [x] A window that crosses midnight (22:00 to 06:00) works, and belongs to the day it starts on.
      Unit test.
- [x] Launching, or waking from sleep, inside a window arms; outside one does nothing. Unit test on
      the rule; manual check across a sleep.
- [x] Arming on schedule uses the launch countdown and the "OnCue is arming itself" notification
      from 0018, so a Mac that arms itself says so. Manual check.
- [x] Disarming by hand inside a window stays disarmed until the next window starts; the schedule
      never re-arms over a person's decision the same window. Unit test.
- [x] Arming by hand outside a window is untouched by the schedule: the end time of a window that
      is not running does not disarm anything. Unit test.
- [x] Scheduled arming obeys the same rule as every other arming: nothing arms when no trigger can
      fire, and it says so where a person would look. Unit test.
- [x] The popover says it was armed by the schedule and when the window ends. Manual check.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
**A pure rule.** `Schedule` in `OnCue/Managers/Helpers/Schedule.swift`: a list of windows, each
with start and end as minutes after midnight and a set of weekdays, and
`contains(_ date: Date, calendar:) -> Bool` that answers whether a moment is inside any window
that started on one of its chosen days. Midnight crossing is the one subtlety: a window from 22:00
Friday to 06:00 belongs to Friday, so 03:00 Saturday is inside it if Friday is chosen, whatever
Saturday's setting is. Overlapping rows are just "inside". Stored as an array in defaults.
Everything below is tested against this function.

**Transitions, not polling state.** `RecordingManager` gains `scheduledArmingEnabled`, a check that
runs once a minute while the app is running, at launch after capture reports its devices (the same
point `armAtLaunchIfWanted` uses), and on wake. The check compares "inside a window now" with
"inside a window at the last check" and acts only on the change: entering a window arms with the
launch countdown; leaving one disarms, but only if the schedule was what armed it. Acting on the
transition rather than the state is what keeps a manual disarm from being overridden a minute later,
and keeps the end of a window from disarming something a person armed outside it.

**Who armed it.** A flag, `armedBySchedule`, set when the schedule arms and cleared by any disarm.
Leaving a window disarms only when it is set. Disarming by hand clears it and the schedule stays
quiet until the next entry.

**Sleep.** The Mac sleeping inside a window ends capture anyway (0008 records the gap). On wake, the
check runs: still inside the window, arm again; outside it, nothing. The keep-awake assertion is the
existing one, held while armed, so a scheduled window also keeps the Mac awake for its duration.
That's what a schedule is for, and Settings says it plainly next to the times.

**Where it lives in Settings.** Under the login checkboxes: a checkbox "Watch on a schedule" and a
small table of windows, one per row with seven day toggles, a start time and an end time, plus add
and remove buttons, and a note that the schedule only runs while OnCue is open, pointing at Open at
Login. The window grows with the table, which the 0034 fix made automatic. A table is more Settings
than anything there so far; it's what "together or separate" costs, and one row is the common case.

**Popover.** The arm state line already says "Armed"; when `armedBySchedule` is set it says so and
names the end time, so someone looking at a Mac that armed itself knows why and until when. This is
copy, marked.

**Arm-at-login and the schedule together.** Both can be on. Arm-at-login arms once at launch
regardless of time; the schedule then disarms at the next window end only if it was the schedule
that armed. A person who wants "always armed after a restart, and also on a schedule" gets exactly
that, and the two rules never fight because only one of them sets `armedBySchedule`.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [x] A two-minute window on this Mac: arms with the countdown and notification at the start,
      disarms at the end, and a manual disarm in between is respected

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

Copy to convey: the Settings checkbox (watch on a schedule, between these times, on these days);
the note that it only works while OnCue is open, so turn on Open at Login; and the popover's line
that it armed itself on the schedule and when the window ends.

## Tasks
- [x] `Schedule` rule with tests, including midnight crossing and day membership
- [x] The transition check in `RecordingManager`, with tests for enter, leave, manual disarm inside,
      manual arm outside, launch inside, wake inside, and nothing-can-fire
- [x] Settings row and its defaults (marked copy)
- [x] Popover line (marked copy)
- [x] Help page section
- [x] The two-minute window on this Mac

## Verification
- **Built (2026-09-22):** `Schedule` and `ScheduleWindow` in `OnCue/Managers/Helpers/Schedule.swift`,
  Codable, stored as JSON under `scheduleWindows` with the switch under `scheduledArmingEnabled`.
  `Schedule.action(...)` is the transition rule. `RecordingManager` keeps `armedBySchedule`,
  `insideScheduleWindow` (nil until the first look, reset when the schedule changes), a
  once-a-minute timer, and a `clock` closure tests replace; `checkSchedule()` runs from the timer,
  from `deviceAvailabilityChanged` (the launch moment arm-at-login uses), from `systemDidWake`, and
  after a defaults change that altered the schedule. Any `disarm()` clears the flag. Scheduled
  arming uses `launchCountdown` and fires `onArmedAtLaunch`, so the 0018 notification posts.
- One refinement to the wake rule, found writing the tests: a wake inside a window arms only if the
  window *started* during sleep. Sleeping and waking inside the same window keeps the last look, so
  a manual disarm before the nap still holds. The spec's "waking inside a window arms" is read as
  that; the alternative would re-arm over a person's decision every time the lid closed.
- Settings: built in code under the folder note, a checkbox, one `ScheduleRowView` per window
  (seven day checkboxes from the calendar's own short symbols, two hour-minute pickers, remove), an
  add button that starts a row at weekdays nine to five, and the note. The view's bottom pin moves
  from the folder note to this section; the window is resized on every rebuild.
- Popover: `armedStateDescription` says "Armed on schedule until <time>" while `armedBySchedule`,
  and the description's KVO dependencies include the flag. Marked, as is every string above.
- Tests: 17 in `ScheduleTests` on the rule and the transition, 10 in `ScheduledArmingTests`
  driving a real `RecordingManager` with a fake clock and its own defaults suite: launch inside and
  outside, enter and leave, manual disarm holding, manual arm left alone, wake across a start, wake
  after a manual disarm, nothing can fire, the window end, and a schedule change taking effect.
- **Seen on this Mac (Jake, 2026-09-22):** the Settings section with two rows; a row set 19:14 to
  17:00 armed by itself within the minute, the popover read "Armed on schedule until 17:00", and
  the window's end disarmed it by itself, a few seconds late. Two things came out of that and went
  in as follow-up commits: a row whose end is earlier than its start now says "next day", and the
  popover's "until" says "tomorrow" (or the weekday) when the end isn't today. The lateness was
  the minute timer firing at the second the app had launched; it now fires on the minute.
- **Seen (Jake, 2026-09-22):** Disarm pressed inside a window held until the window's end. That
  was the last manual check; the gate is complete.

## Open questions
1. Resolved (Jake, 2026-09-22): arming. Version 2's feature was scheduled arming too, so this is
   the same shape: the schedule decides when OnCue is watching, and recordings still start on
   motion or sound.
2. Resolved (Jake, 2026-09-22): a manual disarm stays disarmed until the next window starts. "A
   manual disarm means the user wants it stopped; if they want it started again they can.
   Re-arming feels like a violation of intent."
3. Resolved (Jake, 2026-09-22): both, "together or separate". The schedule is a list of windows,
   each with its own days and hours, so weekdays nine to five and Saturday ten to two are two rows.
   Design and the Settings section updated to a table.
4. Resolved (Jake, 2026-09-22): the countdown and the notification stay. A schedule implies nobody
   is there, in which case they cost fifteen seconds of watching and nothing else; when someone is
   there after all, working late on a Tuesday, they're the only thing that says the camera is
   about to come on.
5. Resolved (Jake, 2026-09-22): leave arm-at-login alone. Both rules run; a window's end undoes
   only what the schedule armed.

## Closure
Shipped in 4.9 (2026-09-22), direct and tap, build 865 uploaded to App Store Connect by the
release script's own store section, the first time that line ran unopposed.
