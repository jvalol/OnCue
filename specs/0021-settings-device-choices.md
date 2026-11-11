---
title: Label the Settings device pickers, and let there be no first camera
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-19
commits: 26a3d57, a599698 (spec), de9d596, 21ebc13, 75f16c0 (implementation)
---

## Problem
Settings opens with three unlabelled pop-up buttons stacked on top of each other. Nothing says
which is the camera, which is the second camera, and which is the microphone, so the fact that
OnCue can watch two cameras at once is invisible unless you already know. Jake read the window as
naming the same camera twice and couldn't tell a second one was a feature.

Separately, the first camera picker lists only connected cameras. There is no way to say "no
camera", even though the trigger rules already allow sound on its own with a microphone and no
camera. A sound-only setup is reachable by unplugging hardware but not by choosing it.

## Non-goals
- Redesigning the rest of the Settings window: the checkboxes, the number fields, and the
  recordings folder row stay where they are.
- The popover. What it shows for a sound-only setup follows from existing rules, and anything more
  is its own spec.
- The preview window's layout with one camera or none.

## Behaviour (acceptance criteria)
- [x] Each of the three pickers has a visible label saying what it chooses. Manual check.
- [x] Each picker shows its "none" entry when nothing is chosen, and neither camera row claims to
      be more optional than the other. Manual check.
- [x] The first camera picker offers a "no camera" entry. Unit test on the preference rule, plus a
      manual check that choosing it leaves OnCue running on the microphone alone.
- [x] Choosing "no camera" is remembered across a restart, and is not overwritten by a camera
      connecting. Unit test.
- [x] With no camera and the sound trigger off, Arm is unavailable, the same as when the last
      camera is unplugged. Unit test against the existing arming rules.
- [x] Choosing "no camera" for the first clears the second, so a single camera is always the
      first one. Unit test.
- [x] The two camera pickers never name the same camera. Unit test (the rule landed in de9d596;
      this keeps it).
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- `Main.storyboard`: a label above each picker, so the window grows taller rather than wider. Its
  size is set in the storyboard and has to grow to match.
- Copy: three labels naming the camera, the second camera, and the microphone, and an entry for
  "no camera" in the first picker. Plain nouns, with no qualifier on the second camera: once the
  first picker offers "no camera", both rows are equally skippable, and tagging only the second as
  optional claims an asymmetry the window doesn't show. The menus carry optionality themselves.
  Proposed with markers, as usual.
- `SettingsViewController`: add a "no camera" item to the first picker, mirroring the existing
  `noSecondCameraID` and `systemInputID` sentinels, which are both the empty string.
- `CaptureManager.changeVideoCaptureDevice` takes a non-optional `AVCaptureDevice` today, unlike
  `changeSecondVideoCaptureDevice` and `changeAudioCaptureDevice`, which both take an optional. It
  becomes optional to match.
- `DevicePreference.preferred` falls back to the first available device when nothing is saved, so
  "chose no camera" has to be distinguishable from "hasn't chosen yet". The empty-string sentinel
  does that, but the rule needs to say so explicitly rather than relying on the caller.
- Connecting a camera while "no camera" is chosen must not switch to it. `shouldSwitch` returns
  true whenever nothing is in use, which is exactly this case, so that rule needs the sentinel too.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [x] The Settings window still fits its content at its storyboard size, with no clipped labels

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

## Tasks
- [x] Labels in the storyboard, and the window resized to fit
- [x] "No camera" in the first picker
- [x] `changeVideoCaptureDevice` takes an optional
- [x] The preference rules learn the "no camera" sentinel, with tests
- [x] Manual checks, Verification filled in

## Verification

**Built, 2026-09-19.** 108 tests pass, clean build, no new warnings. `ibtool` compiles the
storyboard with no errors, warnings, or ambiguity notices, so the new labels don't break the
layout.

Covered by tests: `noDevice` means no device rather than falling back (`preferred`); a camera
connecting doesn't undo the choice (`shouldSwitch`); no first camera means no second and nothing
offered for it (`second`, `secondChoices`); and Arm is already unavailable with no camera and the
sound trigger off (`RecordingManagerTests` line 96, which predates this spec).

Reaching the popover needs no new wiring: `reconfigure(camera: nil)` already runs through
`reportDevices`, which tells `RecordingManager` no camera is available and auto-disarms. That's
the same path an unplugged camera takes, which is what question 3 asked for.

Not covered by a test: that choosing "no camera" clears the saved second camera. It happens in
`changeVideoCaptureDevice`, which writes to `UserDefaults` and reconfigures capture, so it's a
manual check rather than a unit test.

**Manual check, 2026-09-19.** The window reads correctly: labels above each picker, nothing
clipped. Choosing "No camera" leaves the second picker showing "No second camera" with nothing
else to pick, and OnCue keeps running on the microphone alone. In the popover, motion's Trigger is
disabled with no device named, the sound meter is live, and Arm stays available because sound can
still fire.

The second camera's label was "Second camera (optional)" and Jake called it: with the first picker
now offering "No camera", both rows looked equally optional, so the qualifier claimed a difference
the window didn't show. It's a plain "Second camera" now.

## Open questions
1. Resolved (Jake, 2026-09-19): labels go above each picker. The window grows taller, not wider.
2. Resolved (Jake, 2026-09-19): a single camera is always the first one. Choosing "no camera" for
   the first clears the second, so there's no state where OnCue watches only through the second
   pipeline.
3. Resolved (Jake, 2026-09-19): choosing "no camera" behaves exactly like the last camera being
   unplugged. One behaviour, already written and tested.
