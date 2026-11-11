---
title: Choose the recording resolution in Settings
status: abandoned   # draft → approved → shipped | abandoned
created: 2026-09-21
commits: <filled in as work lands>
---

## Abandoned, 2026-09-21
Not built, and the reasoning is worth keeping because it points somewhere else.

Lowering the resolution would not make recordings smaller: the bitrate is pinned at 8 Mbit/s
whatever the frame size, so it would spend the same bits on fewer pixels and look better at the
same cost. The knob for disk use is bitrate, and asking someone to reason about bitrate to get a
smaller folder is friction most people won't get through.

The ultimate concern, a folder that grows until something has to give, is already answered by spec
0029's limit in GB: one number with an obvious meaning. And the proximate cause turned out not to
be file size at all. Jake's own two days of testing made 297 files averaging 18.8 MB, which is
about 19 seconds each against a floor of roughly 10 for a single brief trigger. The folder grows
because OnCue records 150 times a day, not because each recording is large.

That's spec 0033.

## Problem
OnCue never asks what resolution to record at. `CameraPipeline` sets `session.sessionPreset = .high`
and takes whatever the camera's best is, which on a current Mac camera is 1080p or better.

That's one answer for every situation, and the situations differ. A camera watching a doorway at
close range has pixels to spare. A Mac doing something else while it watches has CPU it would
rather keep. Someone recording all night has a folder that grows at a rate they didn't choose.

## What makes this hard
The obvious reason to want this, smaller files, is not what it would do as things stand.

`kVTCompressionPropertyKey_AverageBitRate` is fixed at 8 Mbit/s regardless of resolution. Dropping
from 1080p to 720p therefore doesn't make a recording smaller, it makes it better looking at the
same size, because the same bits describe fewer pixels. The knob that changes how much disk a night
costs is the bitrate, and it isn't exposed either.

So "resolution" is probably not one setting. It's up to three things a user might actually want,
and they pull in different directions:

- **Smaller files.** Bitrate. Directly the thing specs 0029 and 0031 exist to manage.
- **Less work while watching.** Resolution. The motion diff runs on the GPU per frame and the
  sampling pass reads pixels on the CPU, and both scale with the frame.
- **A sharper picture.** Resolution, and bitrate to carry it.

## Non-goals
- Per-camera resolution, at least to begin with. Two cameras that disagree is a second decision.
- Changing what the preview window shows. It scales whatever it's given.

## Behaviour (acceptance criteria)
- [ ] Settings offers resolutions the chosen camera actually supports, not a fixed list. Unit test
      on the rule that picks them.
- [ ] A camera that doesn't support the saved choice falls back rather than failing. Unit test.
- [ ] Changing it takes effect without losing a recording in progress. Manual check.
- [ ] `scripts/check` passes.
- [ ] No `[COPY - Jake]` marker remains in shipped copy.

## Design
Nothing settled. The shape depends on the open questions, but two facts constrain it:

- `AVCaptureDevice.formats` is the honest source for what a camera can do, and it varies per device.
  A fixed menu of 1080p/720p/480p would offer things some cameras can't do and hide things they can.
- `MotionDetectMetalRenderer` reconfigures when the format changes, and `CameraPipeline` already
  handles a device swap, so changing resolution is closer to swapping cameras than to a new
  mechanism.

## Gates
- [ ] `scripts/check` passes (no copy markers, clean build, unit tests green)

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

## Tasks
- [ ] Settle what the setting is for, then draft the design

## Verification
What was actually checked, filled in as it happens: tests, a run on this Mac, a recording on disk.

## Open questions
1. What is the setting actually for? If it's smaller recordings, resolution is the wrong knob and
   bitrate is the right one. If it's a quieter Mac, resolution is right and bitrate is irrelevant.
   If it's both, that's two settings, and two settings about video quality is a preferences pane
   nobody reads.

2. Is there a measurement that would settle it? What 1080p actually costs against 720p, in CPU and
   GPU time per frame, is knowable rather than arguable, and if the answer is "not much" then the
   "quieter Mac" reason goes away and this becomes a bitrate setting. Worth measuring before
   designing anything, the way the rollover seam was.

3. Does anyone need this, or is the real want "OnCue uses less disk", which 0029 and 0031 already
   answer with a limit? A limit is one number with an obvious meaning. A resolution menu asks the
   user to reason about codecs to get the same outcome.
