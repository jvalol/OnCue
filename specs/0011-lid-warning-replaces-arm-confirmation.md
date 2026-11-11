---
title: Lid warning replaces the arm confirmation
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-19
commits: 8f660cb (spec), 3c65c75 (implementation)
---

## Problem
Spec 0008 tried asking for confirmation before arming whenever closing the lid would stop OnCue. On
a laptop without an external display, that's every arm, and Jake found it adds friction for a point
the popover can make without a dialog.

## Non-goals
- The wake notification and the "wasn't watching" line; those stay as they are.
- The lid-risk rule itself.

## Behaviour (acceptance criteria)
- [x] Pressing Arm arms straight away, with no confirmation, whatever the lid risk. Manual check.
- [x] The lid warning line shows whenever the risk is present, unarmed included, so it's in view
      above Arm before pressing it. Unit test on the notice choice; manual check.
- [x] A "wasn't watching" gap still outranks the warning, and still shows only until disarm. Unit
      test.
- [x] `scripts/check` passes.

## Design
- Remove `confirmArmingDespiteLidRisk` and its alert from `PopoverViewController`.
- `PopoverNotice.notice` shows `.lidWouldStopWatching` regardless of arm state; a gap still needs
  armed (it's cleared on disarm anyway). The existing test that nothing shows while unarmed changes
  to cover only the gap.
- The warning's wording stays as shipped ("Closing the lid will stop OnCue until it's opened again"),
  which reads correctly before arming too.

## Gates
- [x] `scripts/check` passes

## Tasks
- [x] Notice shows the lid risk while unarmed, tests updated
- [x] Remove the arm confirmation
- [x] Manual check, Verification filled in

## Verification
- `SleepRiskTests`: the warning shows with the risk armed or not and never without it; a gap shows
  only while armed; a gap still outranks the warning. 62 tests pass on a clean build with no
  warnings (`scripts/check`).
- Jake's manual check (2026-09-19): the warning shows before arming, and Arm arms with no dialog.

## Open questions
None.
