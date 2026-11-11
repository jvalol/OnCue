---
title: Choose the microphone in Settings
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-19
commits: 2fe35b9 (spec), 9acece5 (implementation)
---

## Problem
OnCue records from the first microphone macOS lists, with no way to choose another. On a Mac with
a webcam mic, a USB mic, or an audio interface, it may listen and record through the wrong one,
which matters for the sound trigger from spec 0002.

## Non-goals
- Input gain or level controls.
- Recording from more than one mic.
- Changing how the camera is chosen (spec 0004).

## Behaviour (acceptance criteria)
- [x] Settings has a microphone picker beside the camera picker. Its first entry follows the
      input chosen in macOS Sound settings and is the default; the connected mics follow it.
      Manual check.
- [x] While following the system input, changing the input in macOS Sound settings switches
      OnCue's mic, through the spec 0003 interruption path. Manual check.
- [x] Picking a mic switches capture to it through the spec 0003 interruption path: a recording in
      progress continues in a new file. Manual check.
- [x] A specific mic, once chosen, is saved and used at launch and on reconnect when it's
      connected, otherwise the system input, following the camera rule from spec 0004. Unit test on
      the rule; manual check across a relaunch.
- [x] The picker lists newly connected mics without reopening Settings. Manual check.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- Spec 0004's `DevicePreference` rules are already generic; the mic uses them, keyed by
  `AVCaptureDevice.uniqueID`, with no saved ID meaning "follow the system input".
- The system input is `AVCaptureDevice.default(for: .audio)`. Changes to it are observed with a
  Core Audio property listener on the default input device; the exact API gets confirmed while
  building.
- `CaptureManager` gains `changeAudioCaptureDevice`, mirroring the camera, and `reconfigure` takes
  both devices.
- The picker's label and the system-input entry's title are copy: the drafts carry `[COPY - Jake]`.
- **Decisions while building (2026-09-19):**
  - The camera picker has no label, so the mic picker doesn't either; it sits directly below the
    camera picker. The only new copy is the system-input entry, drafted as "System default".
  - `DevicePreference.preferred` gains a `fallback`, the system input here, used before the first
    available device.
  - The system input is followed with a Core Audio listener on
    `kAudioHardwarePropertyDefaultInputDevice`, delivered on the session queue; it acts only while no
    specific mic is saved.
  - A mic connecting uses spec 0004's `shouldSwitch`: added when capture has none, switched to when
    it's the saved mic returning. With no mic saved, macOS usually makes a newly plugged mic the
    system input, and the listener follows that.

## Gates
- [x] `scripts/check` passes
- [x] Manual checks with a second mic (the webcam's)

## Tasks
- [x] Mic preference through `DevicePreference`, with "follow the system input" as the default, with tests
- [x] Follow changes to the system input
- [x] Save and apply the chosen mic
- [x] Settings picker, refreshed on connect and disconnect
- [x] Manual checks, Verification filled in

## Verification
- `DevicePreferenceTests` adds the fallback rule: the saved mic when connected, else the system
  input, before the first available. 45 tests pass on a clean build with no warnings.
- `scripts/ship-check` failed on the draft "System default" entry until Jake had the marker struck,
  keeping the drafted text.
- Jake's manual checks on the real app (2026-09-19): all pass, including the picker leading with
  "System default", following the system input, and the chosen mic across a relaunch.

## Open questions
Resolved by Jake, 2026-09-19:
- The picker leads with an entry that follows the macOS system input, and that's the default.
