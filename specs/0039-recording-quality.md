---
title: Choose the recording quality
status: abandoned
created: 2026-09-22
commits: <filled in as work lands>
---

## Abandoned, 2026-09-22
Approved, measured, and then dropped on the measurement. Resolution changes nothing a person would
notice about the Mac's work: 12 to 15% of one core armed and watching at 1080p and the same at 720p,
the motion diff already under 1.5 ms of a 33 ms frame. That was the argument 0032 rested on and the
one this spec inherited. What survives is disk, a real 4× span in bitrate (60, 30, 15 MB per minute),
which only changes how many hours the GB limit (0029) holds before it starts deleting, at the price
of every recording looking worse. Nobody has asked for that trade; the review asked for "quality
settings" in a list of things version 2 had. Jake: "the deltas in those values make it seem not
worth it."

If it comes back, it comes back as a retention want (a week of footage on a small disk), and the
hard part is already in Verification: on macOS the session preset can't cap this camera and a
format set before `startRunning` is undone by it; `activeFormat` set after start is what works.

## Problem
OnCue records at whatever the camera's best is (`session.sessionPreset = .high`, 1080p or better
on a current Mac) at a fixed 8 Mbit/s (`kVTCompressionPropertyKey_AverageBitRate`, the same number
`TriggerCost.assumedBitsPerSecond` uses to estimate disk). Nobody chose either, and the situations
differ: a doorway at close range has pixels to spare, a Mac doing other work while it watches has
CPU it would rather keep, and an all-night watch fills a folder at a rate nobody picked.

Spec 0032 asked for a resolution setting and was abandoned on the reasoning that resolution alone
doesn't shrink recordings: the bitrate is pinned, so fewer pixels just look better at the same
size. That reasoning stands. The want behind "quality settings", which the most detailed App Store
review lists among the things version 2 had, is really three wants pulling different ways: smaller
files (bitrate), less work while watching (resolution), a sharper picture (both). Two knobs that a
user has to reason about codecs to combine is the friction 0032 refused. One knob with named
choices, each a sensible pair, is the shape this spec proposes.

## Non-goals
- Separate resolution and bitrate controls. One choice, each choice a pair.
- Per-camera quality. Both cameras follow the one setting (0032's non-goal, kept).
- Frame rate, codec (H.264 stays), or the preview window, which scales whatever it's given.
- Reconfiguring a recording in progress. A change applies to the next recording.

## Behaviour (acceptance criteria)
- [ ] Settings offers a recording quality with three named choices. The default is the top one,
      which is exactly today's behaviour, so nobody's recordings change until they choose.
      Manual check.
- [ ] Each choice maps to a resolution cap and a bitrate. The mapping is one table, unit tested.
- [ ] A camera that can't reach the cap records at its best format under it; one that can't reach
      any of them records at what it has. Unit test on the format-picking rule, against a list of
      formats rather than a device.
- [ ] The encoder's bitrate and the capture format follow the choice. Manual check by recording
      at each and reading the file's dimensions and size.
- [ ] The trigger-cost line and the disk estimate use the chosen bitrate, not the constant.
      Unit test.
- [ ] Changing the choice while a recording is running finishes that recording as it started and
      applies to the next one. Manual check.
- [ ] `scripts/check` passes.
- [ ] No `[COPY - Jake]` marker remains in shipped copy.

## Design
**Measure first, then set the numbers.** The abandoned spec's open question 2 is still the right
first step: what 1080p costs against 720p in CPU and GPU per frame on this Mac, and what each
bitrate costs in MB per minute. Both are knowable rather than arguable. The measurement is the
first task, its numbers go into the table, and the choice names are fixed now so the shape can be
approved before the numbers exist. Proposed:

| Choice | Resolution cap | Bitrate | Disk | For |
|---|---|---|---|---|
| Best | camera's best | 8 Mbit/s | 60 MB/min | today's behaviour; the sharpest picture |
| Balanced | 720p | 4 Mbit/s | 30 MB/min | half the disk, and 720p carries 4 Mbit/s well |
| Small | 720p | 2 Mbit/s | 15 MB/min | a quarter of the disk, for long watches |

Measured 2026-09-22 (Verification): resolution does not change the Mac's work in any way a person
would notice, so the lower rows use 720p for the picture's sake at their bitrates, not for the CPU.

**One table.** `RecordingQuality` in `OnCue/Managers/Helpers/RecordingQuality.swift`: an enum of
the three choices, each with `maximumHeight` and `bitsPerSecond`, stored in defaults by name.
`format(for: [AVCaptureDevice.Format]) -> Format?` picks the best format whose height is within
the cap, falling back to the smallest available when none fits; it's written against a plain
description of formats (width, height) so it can be tested without a camera.

**Where it lands.** `CameraPipeline` stops setting `.high` and instead sets `activeFormat` from the
rule, the way a device swap already reconfigures it; `MotionDetectMetalRenderer` already follows
format changes. The compression session takes its bitrate from the choice. `TriggerCost` takes
`bitsPerSecond` as a parameter already; `RecordingManager.triggerCost` passes the choice's value
instead of the constant, and the constant becomes the Best row's number.

**When it applies.** The pipeline reads the choice when a recording starts, not on every frame and
not mid-file. A recording in progress keeps its format and bitrate; the pre-roll ring is rebuilt
at the new format once the recording ends, since its frames are the old size.

**Settings.** A popup under the size limit row: three names, no numbers on the menu, a one-line
note under it saying what each trades. Copy is Jake's, marked.

## Gates
- [ ] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [x] The measurement is in this file, with the Mac and camera it was taken on, before the table's
      numbers are treated as decided
- [ ] One recording at each choice on this Mac, dimensions and size read back from the files

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

Copy to convey: the popup's label (recording quality), the three names, and a note that the top one
is the sharpest and the bottom one the smallest on disk and lightest on the Mac.

## Tasks
- [x] Measure: CPU and GPU per frame at the camera's best and at 720p; MB per minute at 8, 4 and
      2 Mbit/s. Record the numbers and the machine here.
- [ ] `RecordingQuality` table and format-picking rule, with tests
- [ ] `CameraPipeline` follows the choice for format and bitrate; pre-roll ring rebuilt on change
- [ ] `TriggerCost` and the disk estimate take the chosen bitrate, with tests
- [ ] Settings popup and note (marked copy)
- [ ] Help page section
- [ ] One recording at each choice, read back

## Verification
- **Measured (2026-09-22, Jake's MacBook Pro M5, HD Pro Webcam C920, a Debug build armed with the
  popover closed, 60 seconds of `ps` samples after 25 seconds of warm-up, GPU time from the
  motion-diff command buffer's own start and end times):**

  | | 1920×1080 | 1280×720 |
  |---|---|---|
  | process CPU, armed and watching | 12.6% to 14.9% | 13.6% to 14.6% |
  | resident memory | 181 to 194 MB | 182 to 186 MB |
  | motion diff on the GPU, per frame | 0.85 to 1.4 ms | 0.45 ms |
  | frames per second | ~30 | ~30 |

  The spread at 1080p is across four runs; one to three recordings started during each sample, so
  the encoder is inside these numbers some of the time. Resolution halves the GPU work of the diff
  and does nothing measurable to CPU or memory: the per-frame cost in this process is fixed
  (capture delivery, texture creation, dispatch), not per-pixel, and it sits at 12 to 15% of one
  core either way. The "quieter Mac" reason for a lower resolution is not supported by this; the
  diff was already under 1.5 ms of a 33 ms frame.
- **Bitrate is what the encoder delivers.** The newest recording on this Mac is 6.86 MB over 6.86
  seconds, 7.99 Mbit/s effective against the 8 Mbit/s target; the earlier 297-file sample averaged
  the same. So MB per minute is arithmetic: 60 at 8 Mbit/s, 30 at 4, 15 at 2.
- **What it took to cap the format, which is the real rule's shape:** the session preset
  `.hd1280x720` left this camera delivering 1080p, and a format set before `startRunning` was undone
  by it (starting the session re-applies the preset and picks a format). Setting `activeFormat`
  after `startRunning` sticks, with the preset left at `.high`. `.inputPriority` does not exist on
  macOS. The Debug-only hooks that found this (`ONCUE_MAX_HEIGHT`, `ONCUE_MEASURE`) are in
  `CameraPipeline` and `MotionDetectMetalRenderer` and come out when the rule replaces them.
- **What the numbers do to the table.** The middle and bottom rows keep 720p, but for a different
  reason than the draft gave: not to save work, which it doesn't, but because at 4 and 2 Mbit/s a
  720p frame has twice the bits per pixel of a 1080p one and looks it. The rows are about disk and
  picture, and the "For" column says so now.

## Open questions
1. Resolved (Jake, 2026-09-22): three named choices, each a resolution-and-bitrate pair. Two knobs
   puts the codec reasoning on the user, which is what sank 0032. The combinations off the
   diagonal (full resolution at a low bitrate, say) aren't offered; if anyone asks, a fourth named
   row is cheaper than a second knob.
2. Resolved (Jake, 2026-09-22): the measurement is the first task, not a gate on approval. The
   shape doesn't move with the numbers; the two lower rows' cells do, and they're filled in under
   this spec. If the numbers changed the shape, that's a Design edit.
3. Resolved (Jake, 2026-09-22): the pre-roll ring is rebuilt at the new format once no recording is
   running. A file that changes size five seconds in plays in QuickTime and badly elsewhere; a few
   seconds of pre-roll lost once, at the moment of the change, is the cheaper failure.
4. Resolved (Jake, 2026-09-22): no frame rate cap inside "Small". Fifteen frames a second of a face
   at a door is a worse identification than thirty, and someone saving disk didn't choose that. If
   the measurement says per-frame work dominates, frame rate gets its own visible row later.
