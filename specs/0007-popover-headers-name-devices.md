---
title: Popover headers name the devices in use
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-19
commits: c8097a2 (spec), f26ecbd (implementation)
---

## Problem
The popover's column headers read "Sound" and "Motion". With a mic picker, a camera picker, and
automatic fallbacks (specs 0003 to 0005), there's no way to tell from the popover which mic and
camera OnCue is listening and watching with.

## Non-goals
- Choosing devices from the popover; that stays in Settings.
- Any other change to the popover layout.

## Behaviour (acceptance criteria)
- [x] Under the "Sound" and "Motion" headers, a smaller second line names the mic and the camera
      in use, and both update when the device changes. Manual check.
- [x] With no device of a kind, its second line is empty; the column is already disabled.
      Manual check.
- [x] A long device name is truncated in the middle to fit its column rather than overlapping.
      Manual check.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- `CaptureManager` already reports device availability to the popover after each configure; that
  report carries the device names instead of booleans, nil meaning absent.
- The headers keep their text. Each gets a second label under it in the small system font and the
  secondary label color, set straight from the device name, so there's no text to build and no new
  copy. The meters move down to make room, and the popover grows by that line's height.
- **Built (2026-09-19):** the delegate's `deviceAvailabilityChanged(camera:microphone:)` becomes
  `devicesChanged(cameraName:microphoneName:)`; availability is a name being present. The name line
  sits 2 points under its header, the meter 8 under the name, and the popover is 16 points taller.
- The name labels truncate in the middle so both ends of a name stay readable.

## Gates
- [x] `scripts/check` passes

## Tasks
- [x] Device names in the availability report
- [x] Name labels under the headers, truncating in the middle; popover layout
- [x] Manual checks, Verification filled in

## Verification
- Clean build with no warnings; 45 tests pass (no new tests: the name is shown as macOS gives it).
  `scripts/check` passed in full once the copy markers were struck.
- Jake's manual checks (2026-09-19): all pass.

## Open questions
Resolved by Jake, 2026-09-19: the device name goes on a smaller second line under each header.
