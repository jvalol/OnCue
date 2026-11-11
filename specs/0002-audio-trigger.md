---
title: Audio level meter and audio trigger, with per-trigger toggles
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-19
commits: eb5ea98 (spec), f386c49 (implementation), 7962381 (amendments)
---

## Problem
OnCue only reacts to motion in frame. A dark room, something happening out of frame, or a noise
like glass breaking never starts a recording. The original 2018 popover mocked up an "Audio
Level" meter and an "Audio Trigger" threshold beside the motion pair, but they were never wired
to anything and were removed in 2020 (`20492c9`).

## Non-goals
- Classifying sounds (speech, glass, alarms). The trigger is loudness only.
- Recording audio when no mic is usable; the video-only behaviour from `d4348a4` stands.
- Changing how motion triggers when it's on, or the recording timeout.
- A separate audio-only recording mode.

## Behaviour (acceptance criteria)
- [x] Sound level is reported on a 0 to 100 scale mapped from the mic's average power in dBFS:
      -60 dBFS or quieter is 0, 0 dBFS is 100, linear in dB between. Unit test on the mapping.
- [x] The audio trigger is off by default and turned on with its own checkbox; the checkbox and
      the slider both persist across launches. While it's off, no sound starts or extends a
      recording. Unit test on the decision with the trigger disabled; manual check.
- [x] With the audio trigger on, sound over the audio threshold while armed starts a recording, the same way motion does.
      Unit test on the threshold decision; manual check: arm, clap near the mic, a file appears
      in `~/Movies/OnCue`.
- [x] Sound over the threshold while recording extends the recording by the timeout, like motion.
      Manual check: keep talking past the timeout, one file covers it.
- [x] The popover shows sound and motion side by side, as the 2018 layout did: sound on the left,
      motion on the right, each meter above its trigger. Manual check.
- [x] With no usable mic, the sound meter, checkbox, and slider are disabled and nothing audio-related can
      trigger. Manual check with mic permission denied.
- [x] Motion has its own enable checkbox, on by default. While it's off, no motion starts or
      extends a recording, and the motion meter keeps showing level. Unit test on the decision
      with motion disabled; manual check.
- [x] Arm is disabled while unarmed and no trigger can fire: motion off, and sound off or no usable
      mic. Disarm always stays available. Unit test on the rule; manual check.
- [x] Turning off the last trigger that can fire while arming, armed, or recording disarms
      automatically, which also ends a recording in progress. Unit test on the rule; manual check.
- [x] Arm and Preview look clearly enabled or disabled in the dark popover. Manual check.
- [x] With motion on, motion triggering behaves exactly as before. Existing tests stay green.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- **Level source:** poll the audio connection's `audioChannels` (`averagePowerLevel`, dBFS) on the
  movie file output about 10 times a second from the session queue. No new capture output is
  needed. Rejected: an `AVCaptureAudioDataOutput` with per-buffer RMS, which is more plumbing
  for the same number.
- **Detector:** `AudioDetector` beside `MotionDetector`: `level(decibels:)` for the 0 to 100 scale
  and `detectSound(level:threshold:enabled:)`, both pure and unit-tested.
- **Shared trigger path:** motion and sound both call one `activityDetected()` in
  `CaptureManager` that starts a recording when armed or reschedules the stop when recording.
  This replaces the start/extend branch now inside `detectMotion`.
- **Reporting:** `CaptureManagerActivityDelegate` gains `soundActivityReported(level:)`; the popover
  smooths it like the motion meter.
- **Settings:** `audioTriggerEnabled` (default false) and `audioTriggerThreshold` in UserDefaults,
  set with `register(defaults:)` rather than the first-launch block, so installs that already ran
  once get the defaults too. The slider starts at 70, about
  -18 dBFS; since the trigger ships off, that's a starting point, not a tuned value.
- **Motion toggle (amendment, Jake 2026-09-19, before the first commit):** `motionTriggerEnabled`,
  registered default true. `MotionDetector.detectMotion` takes `enabled` like the audio detector.
  The motion column's "Trigger" label becomes a checkbox with the same title, so both columns
  match. The 2018 mockup armed each trigger with its own Arm button; per-trigger checkboxes with
  one Arm button keep that choice without two arm states.
- **Arm availability:** `RecordingManager.armingAllowed(state:motionEnabled:audioEnabled:audioAvailable:)`
  is the rule, pure and unit-tested. The popover re-evaluates it when a toggle changes, when mic
  availability changes, and when the arm state changes (KVO on `armedStateRaw`).
- **Auto-disarm (Jake, after watching the first build, 2026-09-19):** `RecordingManager.shouldAutoDisarm`
  shares the "can any trigger fire" test with `armingAllowed`. The popover checks it in the same
  three places it updates the Arm button, and calls `disarm()`.
- **Button style:** Arm and Preview move from the deprecated textured-rounded bezel, which reads as
  disabled even when enabled in the dark popover, to the standard push button.
- **Mic availability:** `CaptureManagerActivityDelegate` gains `audioAvailabilityChanged(available:)`,
  sent on the main queue each time the session is configured; the popover enables or disables the
  sound column from it.
- **UI:** the popover widens to two columns, sound on the left and motion on the right, each with
  its meter above its trigger slider, matching the 2018 mockup (`e504f94`). The audio column adds
  the enable checkbox. The meter shows level even while the trigger is off, so the threshold can
  be set before enabling it. Labels are copy: drafts carry `[COPY - Jake]` and need to say which
  column is sound, which is motion, and what the checkbox turns on. The checkbox sits in the row
  where the motion column has its "Trigger" label, so the two columns' rows line up. The popover
  is 580 points wide, and the Preview button stretches to fill the bottom bar between the float
  and menu buttons.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [x] Manual run on this Mac: clap-to-record and talk-to-extend both work

## Tasks
- [x] `AudioDetector` with tests
- [x] `activityDetected()` shared path in `CaptureManager`, motion moved onto it
- [x] Audio level polling and triggering in `CaptureManager`
- [x] Delegate method; two-column popover with meter, checkbox, slider, persistence
- [x] Disabled state with no mic
- [x] Motion enable checkbox, setting, and detector parameter with tests (amendment)
- [x] Arm disabled while no trigger can fire, with tests
- [x] Auto-disarm when no trigger can fire, with tests
- [x] Arm and Preview as standard push buttons
- [x] Manual checks, Verification filled in

## Verification
- Before building: a standalone script confirmed the movie output's audio connection meters while
  nothing is recording (-36 to -45 dBFS in a quiet room), so no extra audio output is needed.
- `AudioDetectorTests` (5 tests): the dB mapping, clamping, silence and NaN, the threshold boundary,
  and never triggering while disabled. `MotionDetectorTests` adds never triggering while motion is
  disabled. `RecordingManagerTests` adds the arm rule: allowed with a trigger that can fire, not
  with both off or with sound on but no mic, and disarm always allowed; and the auto-disarm rule
  across arming, armed, and recording. 18 tests pass on a clean build with no warnings.
- Jake's first manual pass (screen recording, 2026-09-19 10:53): layout and toggles worked; the
  textured Arm button was too hard to read as enabled or disabled, and turning both triggers off
  while armed left it armed. Both addressed above.
- Jake's manual checks on the real app, after f386c49 (2026-09-19): all pass. The popover layout,
  clap to record, talking to extend, no recording with a trigger off, the sound column disabled
  without mic access, Arm disabled with no trigger that can fire, readable button states, and
  auto-disarm when both triggers go off while armed.
- `scripts/ship-check` failed, as it should, on the two draft labels until Jake had the markers
  struck ("Sound" and "Trigger" as drafted). `scripts/check` passes in full.
- Manual checks on the real app: not yet run.

## Open questions
None. Resolved by Jake, 2026-09-19:
1. The audio trigger ships off, with a separate enable checkbox.
2. No default threshold to tune, since it ships off.
3. Side by side, like the 2018 layout.
4. A mic plugged in while running is picked up only at launch or on a camera switch, as today.

Raised with the motion toggle, resolved by Jake the same day:
5. Arm is disabled while no trigger can fire.
