---
title: Watch only the parts of the picture you choose
status: shipped
created: 2026-09-22
commits: f3c60b7 (approval), 108b47f (implementation), 355f600 (the aspect-ratio fix it uncovered), f9d1c39 and 7eeedb4 (built state, manual checks), 5c5f46b and 729c5b8 (released in 4.10)
---

## Problem
OnCue counts motion across the whole frame. A camera pointed at a room with a cat bed in one
corner records every time anyone crosses the room; a hallway camera meant for the door fires for
the window's curtain and the reflection on the floor. The threshold slider can't express "there,
not there": it only says how much of the whole picture has to change, and the parts that matter
are usually a small fraction of it.

The preview already shows exactly what the sampler sees, and it's the natural place to say where
to look. Draw a rectangle around the cat bed, or the door, and motion outside it isn't counted.
Version 2 didn't have this; the requests that describe it use other words ("it records my cat,
not the door") and the App Store reviews about "recording constantly" are the same complaint from
the other side.

## Non-goals
- Shapes other than axis-aligned rectangles. A door and a cat bed are rectangles; a polygon tool
  is a drawing app.
- Per-zone thresholds, per-zone schedules, or sound zones. One threshold per camera as now, and
  sound is not spatial.
- Changing the mask or the kernel. The mask stays whole-frame and byte-identical (0040, 0041); the
  zones decide which of its sampled pixels are counted.
- Zones on the recording. The file is the whole frame, always; zones are about when to record,
  not what to keep.

## Behaviour (acceptance criteria)
- [x] With no zones set, nothing changes: the whole frame is counted, as today. Unit test.
- [x] With one or more zones set for a camera, only sampled pixels inside a zone count, and the
      motion level is the marked fraction of the sampled pixels inside the zones, so a small zone
      full of motion reads as full scale, not as a sliver of the whole frame. Unit test on the
      counting rule against a synthetic mask.
- [x] Zones are per camera, stored in normalised picture coordinates (0 to 1 on each axis), so
      they survive a resolution change and a camera swap keeps each camera's own. Unit test on the
      store and on the mapping between normalised and pixel coordinates.
- [x] In the preview window, a drag on the picture draws a zone; clicking a zone selects it; the
      Delete key removes it; dragging a selected zone moves it; a button clears all. Manual check.
- [x] While zones exist, the preview shows them as outlines and dims the picture outside them, so
      what is ignored reads as ignored. Manual check.
- [x] The meter responds to motion inside a zone and not to the same motion outside it. Manual
      check with a hand in and out of a drawn rectangle.
- [x] The second camera has its own zones, drawn on its own preview. Manual check.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
**The rule.** `DetectionZones` in `OnCue/Managers/Helpers/DetectionZones.swift`: a list of
normalised `CGRect`s per camera ID, stored in defaults as JSON under a key derived the way
`MotionDetector.thresholdKey(cameraID:)` derives its own. `contains(x:y:width:height:)` says whether
a pixel is inside any zone; an empty list contains everything. `CameraPipeline.measureMotion`
keeps its stride-20 sampling and asks the rule per sampled pixel, counting `pixelsTested` and
`pixelsWithMotion` only for pixels inside. The level and the trigger then come from
`MotionDetector` unchanged, with the zone as the universe. That's the whole detection change: one
membership test per sampled pixel, on the CPU, a few thousand per frame.

**The counting rule is pure and tested.** `DetectionZones.count(marked:width:height:stride:)` takes
a closure that says whether a pixel is marked and returns `(tested, withMotion)`, so the tests run
it against synthetic masks with known marked regions and known zones, no camera involved.

**Editing, in the preview window.** `PreviewMetalView` already maps view points to texture points
and back (`texturePointForView`, `viewPointForTexture`), which is the aspect-fit arithmetic the
editor needs. A `ZoneEditorView` sits over each preview view: it draws the zones as outlines from
the normalised rects, dims outside them, and handles mouse events: drag on empty picture draws,
click selects, drag on a selected zone moves, Delete removes, Escape deselects. Edits write
through to `DetectionZones` and the pipeline reads the store on each frame (a few rects; no need to
cache). A small button in the window, "Clear zones", removes them all for that camera.

**Dimming outside the zones.** Drawn by the editor view as an overlay (a translucent black path
with the zones cut out), not by the kernel. The kernel and its two outputs stay as 0040 and 0041
left them; this is a layer on top of the preview, so it's also what shows when the preview is the
plain picture.

**Both cameras.** Each preview view has its own editor bound to its camera ID. The second camera's
zones live under its own key and are only read by its own pipeline.

**No zone means everything.** The default for every camera, and what "Clear zones" returns to, so
nobody who never opens the preview sees any change.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [x] On this Mac: a zone drawn around part of the picture, a hand moved inside it and outside it,
      the meter answering only the inside; a resolution the same, a restart, the zone still there
- [x] Two cameras, each with its own zone, each meter answering only its own

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

Copy to convey: the clear-zones button; a one-line hint in the preview window that dragging draws a
zone and that with none drawn the whole picture counts; and a help page section saying what zones
are for and that recordings are still the whole frame.

## Tasks
- [x] `DetectionZones` store, membership, and the counting rule, with tests
- [x] `CameraPipeline.measureMotion` counts through the rule
- [x] `ZoneEditorView`: draw, select, move, delete, clear, outlines and dimming
- [x] Wiring in `PreviewViewController` for both cameras (marked copy)
- [x] Help page section (marked copy)
- [x] The manual checks

## Verification
- **Built (2026-09-22):** `DetectionZones` (normalised rects, per-camera JSON under
  `detectionZones.<id>`, `contains`, the pure `count`, and a locked cache the sampler reads thirty
  times a second). `CameraPipeline.measureMotion` counts through it; the stride and the marked test
  are what they were. `ZoneEditorView` over each preview: rubber-band draw, click to select, drag to
  move, Delete, Escape, a clear button and a hint, dimming outside the zones with an even-odd path,
  outlines white and the selected one yellow. `PreviewMetalView.pictureRect` gives the editor the
  aspect-fitted picture rectangle, updated as frames arrive; `PreviewViewController` binds each
  editor to its camera's ID from `CaptureManager`. Seven tests in `DetectionZonesTests`: none means
  everything, membership in normalised coordinates, survival across a resolution change, any of
  several zones, the level as a fraction of the zone rather than the frame, motion outside every
  zone not counted, and per-camera storage with the cache following a save. Clean build, 302
  tests.
- Not yet seen: everything in the preview window. The editor's mouse and key handling, the
  dimming, the meter answering only inside a zone, a restart keeping the zone, and the second
  camera's own zones are all manual checks on this Mac.
- **Checked on this Mac (Jake, 2026-09-23):** zones drawn, selected, moved, deleted and cleared
  in the preview; the picture dimmed outside them; the meter answering a hand inside a zone and
  not the same hand outside it; the zones still there after a restart; the second camera with its
  own; and the preview window taking the picture's shape with no bars, after `355f600`. Manual
  checks all good.

## Open questions
1. Resolved (Jake, 2026-09-22): the level is a fraction of the sampled pixels inside the zones.
   The slider keeps its meaning, "how much of what I'm watching changed", and a small zone full of
   motion reads full scale. A tiny zone has few samples and a coarser level; that's visible in the
   box the user drew.
2. Resolved (Jake, 2026-09-22): draw, select, move, delete, clear. No resize handles; delete and
   redraw. Handles are their own spec if anyone turns out to adjust a zone rather than redraw it.
3. Resolved (Jake, 2026-09-22): motion outside a zone is still painted, under the dimming. The
   preview never says "nothing there" when the camera sees something; seen, not counted.
4. Noted: the trigger-cost line (0033) counts recordings, not pixels, and is unaffected.

## Closure
Shipped in 4.10 (2026-09-23), direct and tap, build 890 uploaded to App Store Connect by the
release script's store section.
