---
title: Show motion in the preview as a translucent overlay
status: shipped
created: 2026-09-22
commits: 32e264d and 6d09875 (approval, first design then the overlay), e9ac1c2 (implementation), a03e7b9 (renderer tests), b3d1a8f (proof and measurements), 5c5f46b and 729c5b8 (released in 4.10)
---

## Problem
The preview paints a pixel red when it changed between frames and leaves it alone when it didn't.
In practice the red is one flat colour: a hand moving slowly and a door swinging open look the
same, and a whole moving region reads as a solid red blob. The picture says "something changed
here" and nothing about how much, which is the thing a person setting a threshold is trying to see.

The shader (`OnCue/Preview/Shaders/MotionDetect.metal`) does grade the red, but over a range too
narrow to notice. It marks a pixel when the squared RGB difference exceeds 0.2 and writes
`1.5 × difference` into the red channel; that starts at 0.3 and saturates at 1.0 once the squared
difference passes 0.67. Any real motion is past 0.67, so the visible result is binary.

## What the first attempt taught (2026-09-22)
The first design kept the shader's output as the sampler's input and graded only the red channel's
brightness. Built, tested and reverted the same evening: in a real room it was worse. A dark sleeve
moving on a dark background produces small differences, mostly between 0.2 and 0.7 squared, and the
new ramp painted those a red so dim it vanished against the frame. The old flat red was at least
visible. The premise in the first draft, that real motion lives past 0.67 squared, was wrong; Jake's
screen recording shows most marked pixels are small changes. Red brightness alone has no room to
grade in: below about 0.6 it disappears, so a third of the range is all there is.

The meter and the trigger were unchanged throughout (the marking condition and the mask were
identical), but a dim mask reads as insensitivity, and a preview that misleads about sensitivity is
worse than one that says nothing about magnitude.

## Non-goals
- Changing what counts as motion. The meter, the threshold and the trigger stay exactly as they
  are; the sampler reads the same mask it reads today, from its own texture.
- Grading the overlay by how much changed. Pinned as a follow-up (open question 1); this spec
  paints marked pixels one way, so it can't hide a small change the way the first attempt did.
- Showing sub-threshold change. Sensor noise flickers across every frame; painting it makes a
  still room look alive, and the cutoff is also what the meter counts.
- The meters or the menu bar icon, which already grade (0025, 0014).
- Moving the count onto the GPU. The sampler stays on the CPU with its own buffer.

## Behaviour (acceptance criteria)
- [x] The preview shows the camera picture with changed pixels under a translucent red overlay of
      one fixed strength: motion is as obvious as it is today, and the thing that moved stays
      recognisable through it. Manual check.
- [x] Unchanged pixels show the frame untouched. Manual check.
- [x] The motion level and the trigger are unchanged for the same scene: the sampler reads a
      separate mask texture that is exactly what the shader wrote before, frame pixels for no
      change and `(red, 0, 0)` for change. Manual check that the meter reads what 4.9 reads for the
      same movement, with the number, not the picture, as the evidence.
- [x] The second texture costs nothing a person can see: frame rate and the GPU time of the diff,
      measured the way 0039 measured them, before and after. Recorded here.
- [x] Recordings are untouched; the encoder takes the camera frame. Manual check.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
**Two outputs from one kernel.** `motionDetect` gains a fourth texture. It keeps writing the mask
exactly as today (frame pixel, or `(1.5 × difference, 0, 0, 1)` when the squared difference passes
0.2; not one character of that arithmetic changes), and also writes a preview texture: the current
frame where nothing changed, and where it did, the current frame blended toward pure red by one
constant, `overlay`, starting at 0.5. `MotionDetectMetalRenderer.render` returns both buffers; the
output pool grows to hold the second.

**Who gets which.** `CameraPipeline.processVideo` hands the mask to `measureMotion` on the detection
queue, as now, and the preview buffer to the delegate for `PreviewMetalView`. Nothing else in the
pipeline changes; the recorder never saw either buffer.

**Why it can't go wrong the way the first attempt did.** Detection reads a buffer the preview no
longer touches, so no choice about the picture can move the meter. And the overlay is one strength
for every marked pixel, so a marked pixel is always as visible as any other; there is no ramp to
get wrong. That's what "a little more appealing and less red" costs: nothing.

**Both cameras.** Each pipeline has its own renderer and its own preview view; the second camera
gets the same treatment by construction.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [x] With the preview open: motion is as obvious as on 4.9, the thing moving is recognisable
      through the overlay, and the motion meter's number matches 4.9 for the same movement
- [x] Frame rate and diff GPU time before and after, in Verification

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

No copy. The help page's line about the preview can stay as it is; if it's edited to mention the
overlay, that's Jake's wording.

## Tasks
- [x] The kernel's second output and the renderer returning both buffers
- [x] `CameraPipeline` routing: mask to the sampler, overlay to the preview
- [x] The overlay constant by eye, and the before-and-after measurement
- [x] The manual checks

## Verification
- **Built (2026-09-22):** `motionDetect` takes two more textures: a preview output and the raw
  (unblurred) current frame. The mask output is the 2019 expression unchanged. The preview is the
  raw frame with changed pixels blended toward pure red by `overlay`. `renderWithPreview` returns
  both buffers from the same pool; `render` keeps the protocol and returns the mask.
  `CameraPipeline.processVideo` hands the mask to the sampler and the preview to the window.
  Clean build, 290 tests.
- **Seen on Jake's Mac (2026-09-22), by screen recording:** at `overlay` 0.5 the hand moving read
  as "almost none" visually while the meter sat at full red and the trigger fired, which is the
  separation working as designed and the constant too low for a dark room. At 0.8: "better, let's
  go with that for now." What the overlay covers is the edges and folds of the moving thing, not
  its interior; that's frame differencing on a flat-coloured object and the mask has always been
  that shape. Unchanged areas now show the sharp current frame rather than the blurred previous one,
  since the preview no longer doubles as the mask.
- **The mask rule, proven on the GPU (2026-09-22):** `MotionDetectRendererTests`, four tests that
  run the real kernel on synthetic 64×64 frames inside the app process (so the shader library is
  the app's own) and read the centre pixel: no change leaves the mask as the frame and the preview
  as the frame; a change under the cutoff (squared 0.03) is not marked; black to white is marked
  pure red in the mask and (255, 51, 51) in the preview, which is 0.8 of the way to red; a change
  just over the cutoff has green and blue exactly zero and red above it, the sampler's contract.
  The test target now compiles `MotionDetectMetalRenderer.swift` and `FilterRenderer.swift`. Jake's
  qualitative read: "this works basically intuitively for me"; the number was left to Claude, and
  the tests are that number.
- **Cost, measured (2026-09-22, same Mac and camera as 0039's numbers):** GPU time of the whole
  pass with the second write, 1.374 ms per frame at 1080p, inside the baseline's 0.85 to 1.4. A
  first CPU sample read 31.8% against the evening's 12.6 to 14.9% and looked like a regression, so
  the commit before the overlay was built in a worktree and the two were run alternately, sixty
  seconds each: old 30.6% and 31.2%, new 32.0% and 31.3%, memory 237 to 243 MB on both, with two,
  two, four and zero recordings in the four windows. The builds are indistinguishable; the gap to
  the earlier baseline belongs to the hour (darker room, more recordings) and was the same for
  both. Jake noticed no slowdown.
- **Recordings untouched (2026-09-22):** a frame pulled from the recording made at 22:24:32, while
  the overlay build was the one running, is the plain picture, a hand moving with no red in it.
- **The manual checks:** Jake's, from screen recordings of the preview: at 0.8 motion reads as
  motion and the thing moving is recognisable through it; the trigger fires as before.
- **First design, 2026-09-22:** graded red brightness on the mask itself. Built (a `MotionRamp`
  helper with six tests plus the shader ramp), 296 tests green, seen on Jake's Mac and reverted the
  same evening; see "What the first attempt taught". The helper and its tests were dropped with it;
  nothing of that attempt is in the tree.

## Open questions
1. **Grading: measured and closed (2026-09-23).** Pinned on 2026-09-22 as a one-line follow-up
   with no way to affect detection. Before building it, the sampler got a Debug-only histogram of
   `deltaDotP` over the pixels it marks (`ONCUE_MEASURE`, five bins from the mask's red byte,
   which maps back to `deltaDotP` up to 1.667 and saturates past it). Ninety seconds in Jake's
   room, two cameras, 26,000 and 42,000 marked samples: 45% of marked pixels lie in 1.2–1.3, 24%
   in 1.3–1.4, 13% in 1.4–1.5, 10% in 1.5–1.667, and 8% at or past 1.667, on a scale whose top is
   3. Seven in ten marked pixels are within 0.2 of the cutoff; nine in ten are within 0.47. Any
   ramp over the range puts nearly all real motion at its dim end, which is what the first design
   did, so there is no room to grade in. Closed on the measurement; the histogram stays in the
   Debug build beside the GPU timer.
2. Resolved (Jake, 2026-09-22): 0.8. Tried 0.5 first; in a dark room the edges a difference marks
   need most of the way to red to read as motion.
3. Resolved (Jake, 2026-09-22): the cutoff stays where it is.

## Closure
Shipped in 4.10 (2026-09-23), direct and tap, build 890 uploaded to App Store Connect by the
release script's store section.
