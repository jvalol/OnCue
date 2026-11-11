---
title: Preview window title names the camera
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-19
commits: 2fe35b9 (spec), 9acece5 (implementation)
---

## Problem
The preview window's title always reads "OnCue". With more than one camera, and with OnCue now
falling back to another camera on its own (specs 0003 and 0004), there's no way to tell from the
preview which camera it's showing.

## Non-goals
- Any other change to the preview window.
- Showing the microphone.

## Behaviour (acceptance criteria)
- [x] The preview window's title is "OnCue - " followed by the name of the camera in use, and it
      updates when the camera changes (a switch in Settings, a fallback, a reconnect). Unit test on
      the title; manual check.
- [x] With no camera in use (audio-only capture), the title is "OnCue". Unit test; manual check.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- `CaptureManager` already tells the preview the camera's aspect ratio each time capture is
  configured. That same call passes the camera, or nil, and `PreviewViewController` sets the
  window title from it.
- The camera's name comes from macOS (`localizedName`). The format, "OnCue - [camera name]", and
  the no-camera "OnCue" are Jake's wording, so no copy markers. A small pure function builds the
  title, so it's unit-tested.
- **Built (2026-09-19):** `PreviewTitle.title(cameraName:)`; `CaptureManagerPreviewDelegate` gains
  `setCameraName(_:)`, sent on the main queue after each configure. The preview reads the current
  camera when it loads and sets the title as it appears, since capture is usually configured before
  the window exists.

## Gates
- [x] `scripts/check` passes

## Tasks
- [x] Pass the camera to the preview delegate on configure; set the title
- [x] Manual checks, Verification filled in

## Verification
- `PreviewTitleTests` (2): "OnCue - MacBook Pro Camera" with a camera, "OnCue" without. 44 tests
  pass on a clean build with no warnings.
- Jake's manual checks on the real app (2026-09-19): all pass.

## Open questions
Resolved by Jake, 2026-09-19: the title is "OnCue - [camera name]", and "OnCue" with no camera.
