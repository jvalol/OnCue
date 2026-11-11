---
title: Arm at login
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-19
commits: 144592d (spec), b0c967c (implementation)
---

## Problem
Open at login (spec 0015) gets OnCue running after a restart, but unarmed, so it isn't watching
until someone opens the popover and presses Arm. For a Mac left watching a room, that's the gap
that matters: the one time it reboots is the one time it isn't recording.

## Non-goals
- Arming on a schedule, or by location.
- Any change to what arming does once it's armed.
- Turning on Open at Login by itself; the two settings stay separate.

## Behaviour (acceptance criteria)
- [x] Settings has an arm-at-login checkbox, off by default. Manual check.
- [x] With it on, OnCue arms itself after any launch, with a fifteen-second countdown first, and the
      popover and menu bar show that as they do for any arming. Unit test on the decision to self-arm; manual
      check across a log out and in.
- [x] The countdown can be cancelled from the popover before it finishes. Manual check.
- [x] With it off, launching changes nothing. Unit test.
- [x] OnCue never self-arms when nothing can trigger (no camera and no mic, or both triggers off),
      following the rule from spec 0003. Unit test.
- [x] When OnCue arms itself, it says so with a notification, so nobody finds it recording without
      having been told. Manual check.
- [x] The help page says a Mac can be set to arm itself after every launch, and what that means for
      anyone else in the room. Manual check.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- A `armAtLogin` setting, read at launch by `AppDelegate`, which starts the existing arming
  countdown rather than arming outright, so the menu bar turns orange and the popover counts down.
- The decision is a pure function of the setting and whether a trigger can fire, so it's unit-tested.
  Any launch arms, not just a login launch: simpler, and the same behaviour however OnCue started.
- The countdown is fifteen seconds, against Arm's five, so there's time to notice and cancel after a
  restart.
- The notification reuses the permission already requested in spec 0008.
- The checkbox label and the notification text are copy: drafts carry `[COPY - Jake]`.

## Privacy
This is the feature that turns OnCue from something a person starts into something that starts
itself. Worth stating plainly on the page and in Settings: a Mac set this way records whoever walks
past it after every restart, whether or not they know OnCue exists. The countdown, the coloured menu
bar icon, and the notification are what keep it visible; the setting stays off unless someone
deliberately turns it on.

- **Built (2026-09-19):** `RecordingManager.shouldArmAtLaunch` is the rule; `armAtLaunchIfWanted()`
  runs when capture first reports its devices, so it never arms before knowing whether anything can
  fire, and only once per launch. `AppDelegate` posts the notification through `onArmedAtLaunch`.
  Note: in Debug builds the existing `startArming` shortcut arms immediately instead of counting
  down (spec 0002), so the fifteen-second countdown only shows in a Release build.

## Gates
- [x] `scripts/check` passes
- [x] Manual checks: a log out and in with it on, and a cancel during the countdown

## Tasks
- [x] Self-arm rule with tests
- [x] Setting, countdown at launch, and the notification
- [x] Help page wording for a Mac that can arm itself
- [x] Manual checks, Verification filled in

## Verification
- `RecordingManagerTests` adds the rule (on only when asked and something can fire; never when
  already armed); `RecordingInterruptionTests` adds arming itself once after launch, announcing it
  once, not arming again after a disarm, and not arming when not asked. 100 tests pass on a clean
  build with no warnings.
- Jake's manual checks (2026-09-19): all pass: arming itself after a launch, cancelling during the
  countdown, and not arming when nothing can trigger.

## Open questions
Resolved by Jake, 2026-09-19: any launch arms, not only a login launch; the countdown is fifteen
seconds; the help page says what this means for others in the room.
