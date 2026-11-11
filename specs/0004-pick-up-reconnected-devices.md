---
title: Pick up reconnected devices and remember the chosen camera
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-19
commits: 49004e4 (spec), 33d0df7 (implementation)
---

## Problem
A camera or mic that connects while OnCue is running is only picked up at launch or on a camera
switch. After spec 0003, devices can drop out mid-session: a bumped USB cable leaves the motion
or sound column disabled until OnCue is relaunched, even once the device is back.

## Non-goals
- Re-arming. If losing a device disarmed OnCue (spec 0003), reconnecting it doesn't arm again.
- Switching away from the chosen camera when some other camera connects.
- Remembering a chosen microphone; a mic picker is spec 0005.

## Behaviour (acceptance criteria)
- [x] With no camera in use, a camera that connects is added to capture, and the motion column
      and trigger become available again. Manual check with the webcam.
- [x] With no mic in use, a mic that connects is added, the sound column becomes available, and
      later recordings include audio. Manual check.
- [x] A device connecting mid-recording ends the current file and continues in a new one that uses
      it, the same way as the interruptions in spec 0003. Unit test on the resume path; manual check.
- [x] A device connecting while a camera and mic are both in use changes nothing. Manual check.
- [x] The camera picked in Settings is saved and used again at the next launch when it's connected;
      otherwise the first available camera is used and the choice stays saved. Unit test on the
      selection rule; manual check across a relaunch.
- [x] While running on a fallback because the chosen camera was unplugged, the chosen camera
      coming back is switched back to, through the spec 0003 interruption path. Manual check.
- [x] Settings shows the chosen camera, and lists a newly connected camera without reopening the
      window. Manual check.
- [x] `scripts/check` passes.

## Design
- `AVCaptureDevice.wasConnectedNotification`: when capture lacks a camera or a mic and the new
  device supplies one, reconfigure through the suspend and resume path from spec 0003.
- The chosen camera is saved by `AVCaptureDevice.uniqueID` in UserDefaults when picked in
  Settings. A pure `preferredCamera(savedID:available:)` picks the saved camera if it's in the
  list, else the first; it's used at launch, after a device is lost, and when one connects.
- A connecting camera triggers a reconfigure only if capture has no camera, or if it's the chosen
  camera and capture is on a fallback.
- **Decisions while building (2026-09-19):**
  - The rules live in `DevicePreference` (`preferred(savedID:available:id:)` and
    `shouldSwitch(toConnectedID:currentID:savedID:)`), generic over the device so spec 0005 can
    reuse them for the mic, and testable without devices.
  - When a device is lost, the camera in use is kept if it's still connected (the loss may have
    been the mic); only otherwise does the chosen-else-first rule pick one.
  - Settings identifies cameras by unique ID rather than by name, since two cameras can share a
    name, and shows the chosen camera even while capture is on a fallback.
  - The resume-on-connect path is spec 0003's `recoverFromInterruption`, already covered by
    `RecordingInterruptionTests`.

## Gates
- [x] `scripts/check` passes
- [x] Manual checks with the webcam

## Tasks
- [x] Listen for connections and reconfigure when a missing device returns
- [x] Save the chosen camera; `preferredCamera` with tests; use it at launch, on loss, on connect
- [x] Settings camera list refreshes on connect and disconnect
- [x] Manual checks, Verification filled in

## Verification
- Unit tests, 42 in total, pass on a clean build with no warnings (`scripts/check`). New:
  `DevicePreferenceTests` (8): the chosen device when connected, fallback to the first, first when
  nothing was chosen, none when nothing is connected; a connecting device used when none is in
  use, the chosen one replacing a fallback, another device changing nothing, the chosen device
  already in use changing nothing.
- Jake's manual checks with the webcam (2026-09-19): all pass: falling back and returning to the
  chosen camera, the choice kept across a relaunch, and another camera connecting changing nothing.

## Open questions
Resolved by Jake, 2026-09-19:
- Remember the camera picked in Settings, across relaunches and reconnects.
- A mic picker, remembered the same way, is a follow-up: spec 0005.
