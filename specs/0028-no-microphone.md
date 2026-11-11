---
title: Let Settings choose no microphone
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-20
commits: 943e107 (spec), dfd6b1d (implementation)
---

## Problem
Spec 0021 gave the camera pickers a "No camera" entry, so sound-only is something you can choose.
The microphone picker never got the matching one. It lists "System default" and the connected
mics, and there is no way to say none, so video-only is reachable only by unplugging hardware.

The asymmetry matters more than it looks. Recording a room without recording what's said in it is
a deliberate and reasonable choice for a security camera, and arguably the more important half of
this pair: a camera pointed at a hallway is one thing, a microphone listening to the conversations
in it is another. Today OnCue makes the first choosable and the second not.

## Non-goals
- Changing what "System default" does. Following the input chosen in macOS Sound settings stays
  the behaviour when nothing is picked.
- Muting a recording after the fact, or a per-recording choice. This is a setting, like the
  cameras.
- A matching option anywhere but Settings.

## Behaviour (acceptance criteria)
- [x] The microphone picker offers an entry meaning no microphone at all. Manual check.
- [x] Choosing it leaves OnCue watching on the camera alone, and recordings have no audio track.
      Manual check on a recording.
- [x] Choosing it is remembered across a restart, and plugging a microphone in doesn't undo it.
      Unit test.
- [x] Choosing no microphone turns the sound trigger off, and choosing no camera turns the motion
      trigger off. Unit test on the rule, plus a manual check on both.
- [x] A device going missing on its own still leaves its trigger alone, so it resumes when the
      device comes back. Unit test.
- [x] With no microphone and no camera, Arm is unavailable. Unit test against the existing rules.
- [x] "System default" still follows macOS, and is still what a fresh install does. Unit test.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- `DevicePreference.noDevice` already means "none, on purpose" as against nil, which means no
  choice yet. `preferred` returns nothing for it and `shouldSwitch` refuses to override it, so the
  rules this needs already exist and are tested (spec 0021).
- The saved values become: nil for system default, `noDevice` for none, a unique ID for a specific
  mic. That's three states in one key, and it works because nil and `noDevice` are different
  things to `preferred`.
- One trap. `SettingsViewController.systemInputID` is the empty string today, which is also
  `noDevice`. It's only ever a menu tag and never saved, so nothing is broken now, but the moment
  `noDevice` becomes a saved value the two collide when the picker looks for which item to select.
  The tags have to be distinguishable.
- `changeAudioCaptureDevice(nil)` means system default today, so "none" can't reuse it. The camera
  got away with `changeVideoCaptureDevice(nil)` meaning none because a camera has no equivalent of
  following the system.
- Turning the trigger off belongs with choosing none, not with the device being absent: the two
  look the same by the time `devicesChanged` runs, and only the picker knows which happened.
- `FileOutputManager.movieName` already drops a missing device from the name, so a recording with
  no microphone is named for its camera alone with no change.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [x] A recording made with no microphone plays, and has no audio track

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

## Tasks
- [x] Tell the menu tags apart from the saved sentinel
- [x] A way to choose none that isn't the way to choose system default
- [x] The entry in the picker, and the sound side going quiet with it
- [x] Choosing none switches off the trigger that depends on it, for the mic and the cameras
- [x] Manual checks, Verification filled in

## Verification

**Built, 2026-09-20.** 160 tests, one skipped (0022's pre-26.2 path), clean build, no new
warnings.

The tag collision the spec flagged was real and is fixed. `systemInputID` and `noSecondCameraID`
were both the empty string, which is also `DevicePreference.noDevice`. They're now
`"system-default"` and `"no-second-camera"`, since both mean an absence of a choice and save nil,
while "No camera" and "No microphone" are choices and save `noDevice`. Left alone, picking "No
microphone" would have shown "System default" as the selected item.

`chooseNoAudioCaptureDevice` is separate from `changeAudioCaptureDevice(nil)` because nil already
means following the system input. The camera didn't need this: it has no equivalent of following
macOS, so nil could mean none there.

`DevicePreference.triggerEnabled` is question 2's rule, and only the choosing path calls it. The
test for a device going missing asserts that through `shouldSwitch` instead, which is what
actually governs a device coming back and already refuses to override a deliberate none.

One thing the wiring needed that the spec didn't foresee: the popover's trigger checkboxes are
read once when it's created, so switching a trigger off in `UserDefaults` left the tick showing.
They're refreshed in `devicesChanged` now, which runs on every reconfigure.

**Manual check, 2026-09-20.** "No microphone" appears last in the picker, a recording made with it
has no audio track, and choosing none unticks the trigger that depended on it, for the microphone
and for the cameras. That last one changes behaviour 0021 shipped, so it was the one worth
watching.

## Open questions
1. Resolved (Jake, 2026-09-20): "No microphone", last in the list. Both follow the cameras: "No
   camera" sits at the bottom of the camera pickers, so someone who has seen it there looks in the
   same place, and the label above the picker says "Microphone", so the plain negation of it reads
   naturally. "System default" stays first, since it's a fallback rather than a choice and putting
   none above it would read as the recommended option.

   Wording that names the consequence, like "Don't record sound", was considered and rejected: a
   Settings window that uses one pattern for cameras and another for the mic costs more than the
   extra clarity repays, and the help page can carry the reason. A picker item is the wrong place
   to make the privacy argument anyway.
2. Resolved (Jake, 2026-09-20): it turns the trigger off, and the same goes for choosing no
   camera.

   Claude argued first for leaving it on, by analogy with a device being unplugged, and that was
   wrong. Hardware vanishing and a device being chosen away aren't the same case: a disconnected
   mic may come back on its own, so resuming as you left it is right, while "No microphone" only
   ends when you change the setting again, at which point you're deciding afresh. A trigger left
   ticked for a device you deliberately removed records an intention you just contradicted.

   `DevicePreference`'s "the choice itself is never cleared" doesn't apply: that's about device
   choices surviving a disconnection, not about trigger toggles.

   This widens the spec. Spec 0021 has the same problem, since choosing "No camera" leaves
   `motionTriggerEnabled` ticked, so both pickers are fixed here rather than leaving the pair
   behaving differently for the same act.
3. Resolved (Jake, 2026-09-20): nothing. The question was mis-framed when drafted. Specs 0024 and
   0027 are about failures, where something went wrong and OnCue looked like it hadn't; a recording
   made with no microphone chosen is the thing that was asked for, and warning about it would be
   OnCue second-guessing a setting.

   The claim that a silent file can't be told from one that lost its mic was also wrong: spec 0009
   already puts the devices in the name, so "… - MacBook Pro Camera.mov" beside "… - MacBook Pro
   Camera + MacBook Pro Microphone.mov" says plainly that no microphone was involved. What it
   doesn't say is why, and the two whys are your own setting, which you know, or a mic that wasn't
   there, which belongs with 0027's family if it ever matters.
