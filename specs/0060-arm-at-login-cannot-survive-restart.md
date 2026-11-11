---
title: Say when arm-at-login can't survive a restart
status: shipped
created: 2026-10-12
commits: 4175758 (approval), 60a392f (implementation), f69900f (built state, manual checks), 0471234 and de0a0db (released in 4.21)
---

## Problem
"Arm OnCue when it opens" (0018) only does anything if something opens OnCue. After a restart,
or a log out and in, that something is Open OnCue at Login. With the first box ticked and the
second off, a restart leaves OnCue closed and the camera unarmed, and the app says nothing: the
state looks like every other morning until the morning it didn't record.

Spec 0051 fixed exactly this mismatch for the schedule. The rule it added,
`ScheduleRisk.cannotSurviveRestart`, looks only at the schedule, so the arm-at-login case still
has no warning. The two checkboxes sit one above the other in Settings, which is why 0051 left it
alone, but the person who needs the warning isn't looking at Settings. They're the one whose
Open at Login turned itself off: every brew and direct user who upgraded through 4.8 lost the
login item to the bundle ID change (0037), and on this Mac the box read off after a restart on
2026-10-08 for that reason. Arm at login was on. Nothing said the two no longer added up.

## Non-goals
- Changing Open at Login on the user's behalf. 0051's reasoning holds.
- Detecting that macOS launched OnCue from a stale login item row. Possible through the launch
  Apple event, but it's a one-time cleanup message for a shrinking group; the warning here reaches
  the same people on every launch until they fix it.
- A new setting.
- Touching the schedule's own note under the schedule section.

## Behaviour (acceptance criteria)
- [x] With Arm OnCue when it opens on and Open at Login off (or awaiting approval), the popover's
      notice line says OnCue won't be open after a restart so it can't arm itself, ranked where
      0051's schedule warning is: a risk that hasn't happened, below every "happened" notice, below
      the fresh start and the update line, above the lid. Unit test on the rule and the ranking.
- [x] The same holds with the schedule on and the arm box off (0051, unchanged), and with both on.
      One notice, not two. Unit test.
- [x] Turning Open at Login on, in Settings or in System Settings, clears it without a relaunch.
      Unit test on the rule from each login state; manual check.
- [x] Turning Arm OnCue when it opens off clears it the next time the popover opens. Unit test on
      the rule; manual check.
- [x] With Open at Login on, nothing changes: no new notice anywhere. Unit test.
- [x] German for any new or changed string; 0043's invariant green. Unit test.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
**The rule grows one input.** `ScheduleRisk.cannotSurviveRestart` takes `armAtLogin: Bool`
alongside `scheduleEnabled` and `hasWindows`, and is true when either a schedule with a window or
arm-at-login is on and the login state isn't `.on`. `current(...)` reads `armAtLogin` from the
same defaults. The type keeps its name; renaming it touches 0051's tests for no behaviour.

**The popover.** `PopoverNotice.scheduleCannotSurviveRestart` stays the case and the rank. Its
string changes to cover both reasons, since the fix is the same sentence either way: turn on Open
OnCue at Login. The popover already re-reads the login state and the rule each time it opens
(0051), so a change to either checkbox shows on the next open with no new observation.

**Settings.** No new note. The arm box is directly under the Open at Login box, and the schedule
note under the schedule keeps saying what it says today. That note read `ScheduleRisk.current`,
which now includes the arm box, so it reads `ScheduleRisk.scheduleOnly` instead: a note that
says "the schedule only arms OnCue while it's open" shouldn't turn orange for a box two sections
up. `handleArmAtLogin` doesn't touch it.

**Help.** The "Arming when you leave" section gets one sentence saying arm-at-login needs Open at
Login for the same reason the schedule does, if it doesn't say so already.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [x] The three existing `ScheduleRiskTests` still pass with the new parameter

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

## Tasks
- [x] `ScheduleRisk.cannotSurviveRestart(scheduleEnabled:hasWindows:armAtLogin:loginState:)` and
      `current(...)` reading `armAtLogin`; tests for arm on alone, both on, arm on with login on
- [x] The popover notice string reworded to cover both reasons, under a marker, with German
- [x] `SleepRiskTests` ranking case: none needed. The notice takes one `scheduleAtRisk` flag and
      the rule is what grew, so the rule's tests are the ones that know about the arm box; the
      ranking tests from 0051 cover the case unchanged
- [x] Help sentence, under a marker
- [x] Changelog and feed entry for the release, with the disclosure line
- [x] Manual check: arm box on, Open at Login off, popover shows the line; turn Open at Login on,
      reopen the popover, it's gone

## Verification
- `scripts/check` green on this Mac, 2026-10-12, after Jake's rewrite of the popover line and
  the help sentence: 438 tests, one skipped, no failures. The four new `ScheduleRiskTests` cover
  arm alone, both reasons, the app's own defaults, and the Settings note ignoring the arm box.
- The line showed in the real popover on this Mac (Jake, 2026-10-12): arm box on, Open at Login
  off after the bundle ID change, the update line paid, and 0060's line took its place.
- Manual checks look good (Jake, 2026-10-12): the line gone after Open at Login is turned on.

## Open questions
1. **A note under the arm box in Settings, or not? Resolved (Jake, 2026-10-12): no note.** The
   mismatch is already on screen there, two lines apart, and the person who needs the warning is
   the one whose Open at Login turned itself off through the bundle ID change, who isn't in
   Settings. The popover line reaches them. A note under the arm box can follow if anyone says the
   window confused them; it costs a storyboard change, a manual catalog entry and German.
2. **One notice string for both reasons, or two? Resolved (Jake, 2026-10-12): one.** The fix is
   the same sentence whatever the reason, so naming the reason adds words without changing what
   the reader does next, and two strings need a third for the both-on case. The existing line
   loses "the schedule" and says OnCue can't arm itself; one string, one German translation, one
   ranking assertion.
