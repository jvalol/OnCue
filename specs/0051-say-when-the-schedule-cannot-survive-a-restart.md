---
title: Say when the schedule can't survive a restart
status: shipped
created: 2026-09-23
commits: 6325e2b (approval), c76464c (implementation), 23b0d9f (built state, manual checks), a2cc7ce and 2dd451b (released in 4.14)
---

## Problem
A schedule only runs while OnCue is open. After a restart, or a log out and in, nothing arms at
nine unless Open OnCue at Login is on. The connection is written once, in a grey note under the
schedule in Settings, and nowhere else. A person who set up a weekday schedule and left Open at
Login off has a camera that stops working at the next restart, and the app says nothing until
the morning it didn't arm. The same holds for the Focus Filter (0050): it can only arm a running
OnCue.

Turning Open at Login on for them isn't the answer. It's a login item, macOS may ask the user to
approve it (0015), it shows under their name in System Settings, and a setting that flipped
itself because a checkbox was ticked is the kind of thing that turns a careful user into a
one-star review. The answer is to make the mismatch impossible to miss.

## Non-goals
- Changing Open at Login on the user's behalf, ever. Not even with a prompt that defaults to yes.
- Detecting whether a Focus Filter is configured. The system doesn't tell the app; only an
  arming by a Focus is visible to it. The Focus half stays in the help.
- A new setting.

## Behaviour (acceptance criteria)
- [x] With the schedule on and Open at Login off (or awaiting approval), the note under the
      schedule in Settings turns into a warning, in the warning colour the popover uses for the
      lid, saying the schedule can't arm after a restart until Open at Login is on. With Open at
      Login on, the note is the grey one it is today. Unit test on the rule; manual check.
- [x] The popover's notice line says the same while the mismatch holds, ranked as a risk that
      hasn't happened: with the lid warning, below every "happened" notice and below the fresh
      start. When both risks apply the schedule's wins, since it's the one the person can fix in
      Settings. Unit test on the ranking.
- [x] Turning Open at Login on, in Settings or in System Settings, clears both without a
      relaunch: the Settings note reverts and the popover notice goes. Unit test on the rule from
      each login state; manual check.
- [x] A schedule with no windows doesn't warn: nothing is coming. Unit test.
- [x] German for the two strings; 0043's invariant green. Unit test.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
**One rule.** `ScheduleRisk.cannotSurviveRestart(scheduleEnabled:hasWindows:loginState:)`, pure,
in `Helpers`: true when the schedule is on with at least one window and the login item is
anything but `.on`. `LoginItem.State` already distinguishes on, off and needs-approval.

**Settings.** `SettingsViewController` computes the rule when it builds the schedule section and
whenever the schedule or the login checkbox changes; the note's text and colour follow it. The
warning colour is `systemOrange`, what the popover's lid line uses.

**The popover.** `PopoverNotice` gains `scheduleCannotSurviveRestart`, ranked with
`lidWouldStopWatching` and above it. The popover reads `LoginItem.app.state` when it updates the
notice, so a change made in System Settings shows the next time the popover opens; the
observations already in place for the schedule (`scheduleGeneration`) cover changes made in
Settings.

**Focus.** Not detectable, so the help's "Arming when you leave" section keeps the sentence
about Open at Login, and the popover says nothing about it.

**Copy.** The Settings warning and the popover line, in English and German.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [x] On this Mac: schedule on, Open at Login off, the orange note and the popover line; turn
      Open at Login on in Settings, both gone; turn it off in System Settings, both back at the
      next popover open

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

Copy to convey: that the schedule can't arm OnCue after a restart while Open OnCue at Login is
off, once for the Settings note and once, shorter, for the popover line.

## Tasks
- [x] `ScheduleRisk` rule with tests
- [x] Settings note text and colour from the rule (marked copy)
- [x] `PopoverNotice.scheduleCannotSurviveRestart`, its ranking, the popover line (marked copy)
- [x] German (marked copy)
- [x] The manual checks

## Verification
- **Built (2026-09-23):** `ScheduleRisk.cannotSurviveRestart(scheduleEnabled:hasWindows:loginState:)`
  and `ScheduleRisk.current(defaults:loginState:now:)`, which reads the schedule and the login
  item ("has windows" is `Schedule.nextStart` non-nil, so rows with no days or no length don't
  count). Settings: `updateScheduleNote()` swaps the note's text and colour, run at build, on the
  schedule checkbox, on every row change, after the Open at Login checkbox, and in
  `viewWillAppear` for a change made in System Settings. Popover:
  `PopoverNotice.scheduleCannotSurviveRestart`, ranked below everything that happened and the
  fresh start, above the lid; the popover recomputes it on every notice update, observes the
  schedule generation for edits made in Settings, and re-reads on open for System Settings.
  Six tests: the rule from each login state, no schedule or nothing coming, from the app's own
  state through defaults, the ranking against the lid and against a failure and a fresh start.
  Clean build, 373 tests.
- **Found on the first check (Jake, 2026-09-23):** a few seconds' delay after toggling Open at
  Login or the schedule. The cause was asking macOS for the login item's status synchronously on
  every change; `SMAppService.status` can block for seconds. Now read once, off the main thread,
  when Settings appears and when the popover opens, and taken from the result of a change made in
  Settings; the note and the notice use the cached state. The popover assumes "on" until the
  read returns, so a slow read delays the warning rather than the popover.
- **Checked on this Mac (Jake, 2026-09-23 21:36):** the orange note and the popover line with the
  schedule on and Open at Login off; both gone when it's turned on in Settings; both back after
  it's turned off in System Settings. One delay seen once after the fix that couldn't be
  reproduced; noted, not chased. Markers read and struck; `scripts/check` passes.

## Open questions
1. Resolved (Jake, 2026-09-23): Open at Login only. A schedule doesn't need "Arm OnCue when it
   opens": once OnCue is open, 0038's launch check arms inside a window on its own, and warning
   about the other setting would push schedule users toward arming at every restart, the
   opposite of what they set up.
2. Resolved (Jake, 2026-09-23): no offer dialog. The orange note appears one line under the
   checkbox the moment it's ticked, in the same window as Open at Login; a dialog would say it
   twice, interrupt people who already know, and on a fresh Mac could lead straight into the
   login-item approval dialog. Comes back only if the note turns out to be ignored.

## Closure
Shipped in 4.14 (2026-09-24), direct download and the tap (cask `fdaf5e6`, `scripts/check-tap`
green). The store version follows once 4.13 clears review.
