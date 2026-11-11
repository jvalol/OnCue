---
title: Skip the preview picture when nothing is showing it
status: shipped
created: 2026-09-22
commits: 212244d (approval), 119cd14 (the Debug-only GPU timer), 8814fde (implementation), 0e7867b and bc2f0eb (built state, manual check, measurement), 5c5f46b and 729c5b8 (released in 4.10)
---

## Problem
Since 0040 the motion kernel writes two pictures a frame: the mask the sampler counts, and the
preview the window shows. The mask is needed whenever OnCue is armed, because detection runs on
it. The preview is needed only while the preview window is open. Right now it is written on every
frame regardless, into a buffer that is handed to a delegate and dropped when no window is showing
it. Armed and unattended, which is the state a security camera lives in, that's a full-frame write
and a full-frame buffer allocation per frame for nobody.

Measured on Jake's M5 MacBook Pro the whole pass is unchanged by it (0040's Verification), so this
isn't a fix for something seen, and the measurement below says the saving is negligible on any
Mac. It's done because writing a picture nobody looks at is wrong on its face and stopping it is
small; not because anyone will notice.

## Non-goals
- Any change to what the preview shows, or to the mask. Both come out byte-identical to 0040.
- A user-facing setting. Jake floated a toggle between the old and new preview; the answer to a
  cost nobody can measure is not a switch nobody can evaluate. This does the saving for everyone.
- Stopping capture, the kernel or the sampler. That's 0023's territory and it already runs only
  when something needs the camera.

## Behaviour (acceptance criteria)
- [x] With the preview window closed, the kernel writes only the mask: no preview buffer is taken
      from the pool and no preview texture is bound. Unit test on the renderer: rendering with the
      preview off returns a mask and no preview, and the mask is identical to rendering with it on.
- [x] With the preview window open, both are written and the preview is what 0040 shipped. Unit
      test (the 0040 renderer tests, unchanged, run with the preview on).
- [x] Opening the preview window starts the preview pictures without a visible gap: the first frame
      after opening has one. Manual check.
- [x] Closing it stops them. Manual check that nothing changes on screen, since nothing is on screen,
      and that the meter carries on.
- [x] The saving is measured the way 0039 and 0040 measured: GPU time per frame and process CPU,
      armed with the preview closed, before and after. Recorded here, whatever it comes to.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
**The signal exists.** `CaptureManager.previewOpen` (0023) is already true exactly while the
preview window is showing, set from the popover's Preview button and from the window's own close.
It reaches capture today to decide whether the camera runs at all; it now also reaches each
pipeline as `wantsPreview`.

**Two pipeline states, one kernel.** The kernel takes a Metal function constant,
`writesPreview [[function_constant(0)]]`, and its preview write sits under `if (writesPreview)`.
The renderer builds two compute pipeline states at init, one per value, and picks by the flag on
each call. Function constants are resolved at pipeline creation, so the mask-only variant carries
no branch and no unbound-texture hazard; that's why this and not a runtime `if` on a uniform.

**The renderer's call.** `renderWithPreview(last:current:preview: Bool) -> (mask, preview?)`. With
`preview` false it takes no preview buffer from the pool, binds no preview texture, and returns nil
for it. `CameraPipeline.processVideo` passes `wantsPreview` and calls the delegate only when it has
a preview to give.

**The first frame after opening.** `previewOpen` flips on before the window is on screen, on the
main queue; the next frame through the pipeline sees the flag and writes a preview. At 30 frames a
second that's within a frame of the window appearing, and the window shows nothing until it gets
a buffer, as now.

**Both cameras.** Each pipeline gets the flag from the same property; the second camera follows.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [x] The before-and-after measurement, armed with the preview closed, in Verification
- [x] Preview window opened and closed twice while armed, the picture appearing at once and the
      meter unaffected

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

No copy.

## Tasks
- [x] Function constant in the kernel, two pipeline states in the renderer, the `preview:` flag
- [x] `wantsPreview` from `CaptureManager.previewOpen` into each pipeline
- [x] Renderer tests: off returns no preview and the same mask; the 0040 tests still pass with on
- [x] Measurement before and after
- [x] The open-and-close manual check

## Verification
- **Built (2026-09-22):** `writesPreview` is a function constant in `MotionDetect.metal`; the preview
  write sits under it. `MotionDetectMetalRenderer` builds both variants at init and
  `renderWithPreview(…, preview:)` picks one, taking a preview buffer from the pool and binding
  textures 3 and 4 only when asked. `CameraPipeline.wantsPreview` is set for both pipelines from
  `CaptureManager.previewOpen`'s `didSet`; the delegate is called only when there is a preview.
  The protocol's `render` asks for the mask alone. Clean build, 295 tests: the 0040 renderer tests
  unchanged with the preview on, plus one that the off variant returns no preview and the same mask.
- The Debug-only GPU timer was kept this time (`119cd14`), with the recipe in CLAUDE.md.
- **Seen (Jake, 2026-09-22):** the preview window opened and closed twice while armed; the picture
  was there at once each time and the meter didn't change.
- **Measured (2026-09-22, Jake's M5 MacBook Pro, C920, 1080p, armed, run turn about with the
  commit before this one, sixty seconds each after a 25-second warm-up):**

  | | GPU per frame | CPU | memory | recordings in the window |
  |---|---|---|---|---|
  | before | 1.036 ms | 24.6% | 199 MB | 1 |
  | after | 0.985 ms | 41.6% | 274 MB | 7 |
  | before | 1.034 ms | 35.0% | 252 MB | 7 |
  | after | 0.936 ms | 31.4% | 253 MB | 7 |

  The GPU number is the clean one, and it is negligible: the pass went from 1.036 to 0.985 ms and
  from 1.034 to 0.936 ms, a saving of 0.05 to 0.1 ms per frame. Against the millisecond-sized pass
  that reads as five to ten percent; against the 33 ms frame a Mac actually has to fill at 30 fps
  it is 0.15 to 0.3 percent, and the frame is the denominator that matters. Jake, on seeing the
  first framing: "0.051 ms difference is totally negligible, not 4.9%." Correct. This change is
  justified as not writing a picture into the void, not as a performance gain. That is the saving, and it is the size
  the spec expected. The CPU and memory columns are confounded twice over: Jake's open-and-close
  manual check ran during the "after" windows, so those had the preview on for part of the time
  (the 274 MB is preview buffers), and the room produced one recording in the first window and
  seven in each of the others. Within that noise the builds are indistinguishable on CPU, which
  matches 0040's finding that the preview was never where the CPU went. On a weaker Mac the pass is
  longer and the saving proportionally the same, which is to say still negligible.

## Open questions
1. Resolved (Jake, 2026-09-22): function constant, two pipeline states. A runtime flag is a branch
   on every pixel and still needs a preview texture bound; two states cost one object at init and
   nothing per frame.
2. Resolved (Jake, 2026-09-22): the popover is not a preview. It shows meters, never pictures, and
   never receives the rendered buffer; only `previewOpen` counts.

## Closure
Shipped in 4.10 (2026-09-23), direct and tap, build 890 uploaded to App Store Connect by the
release script's store section.
