---
title: Two cameras side by side in the time-lapse
status: shipped
created: 2026-10-01
commits: d689f90 (approval), 3275ef8 (implementation), 1da3868 (built state, manual checks), 58e8aa9 and 3c3519d (released in 4.18)
---

## Problem
0055 interleaves two cameras' frames in time order, cutting between rooms every quarter second
with the camera's name to say which is which. It was the honest first version because side by
side needs the two recordings' timelines aligned, and it reads like a security feed cut by
someone in a hurry. The thing a two-camera stretch wants is both rooms on one timeline: the hall
and the kitchen at the same moment, the person leaving one as they enter the other. Side by
side is that, and it replaces interleaving rather than sitting beside it as a setting: it's the
better layout for two cameras in every case but one, half the width per camera, which is the
price of seeing both.

## Non-goals
- No setting. Two cameras in a stretch means side by side; one camera means the full frame, as
  today. Decided with Jake on 2026-10-01: a switch would be a Settings row for a preference
  nobody has asked to make.
- No more than two panels. OnCue records from two cameras at most (0012).
- No change to what's sampled: still first, a frame every two seconds, four a second (0055).
- No synchronising of the recordings themselves. Alignment is by the wall clock in the file
  names, to the second, which is what both cameras were named by.

## Behaviour (acceptance criteria)
- [x] A stretch whose recordings come from two cameras renders every frame as two panels, the
      first camera on the left and the second on the right, each showing that camera's picture
      at the same moment. Unit test on the paired plan.
- [x] The timeline is one grid of two-second steps from the stretch's earliest frame; at each
      step a camera shows the sample from whichever of its recordings covers that moment. A
      recording's still is shown at the first step at or after its start, in place of the
      sample. Unit test.
- [x] At a step one camera has no recording for, its panel is dark with the camera's name, not
      a held frame: a held frame would say nothing is happening when the truth is nothing was
      recorded. Unit test on the plan; manual check on the look.
- [x] The two panels split the canvas evenly, each picture letterboxed into its half. The
      canvas is the first readable frame's size, as today. Unit test on the placement.
- [x] The time is drawn once, bottom-left of the whole frame; each panel carries its camera's
      name at its top. Manual check.
- [x] Which camera is left: the one chosen as Camera in Settings if it's in the stretch,
      otherwise the first by name. Unit test on the rule.
- [x] A one-camera stretch is unchanged: full frame, time only. Unit test that the plan for one
      camera has no pairs.
- [x] Help and the changelog say two cameras are side by side; the strings are under the marker
      with German. Unit test on the catalog.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- **`TimeLapse.pairedPlan(events:durations:left:)`**, beside `plan`. It builds the step grid
  from the earliest frame time to the latest, then for each step and each camera finds the
  recording that covers it (start ≤ step < start + duration, from `recordingDate` and the
  duration table) and emits `.movie(url, offset:)`, or `.still(url)` at the first step at or
  after a recording's start when the still is in the event, or nil for a dark panel. The result
  is `[PairedFrame]` with `time`, `left`, `right` and the two camera names; `hasTwoCameras`
  decides which plan the renderer asks for.
- **Drawing.** `draw(panels:labels:time:into:canvas:)` fills black, letterboxes each image into
  its half, draws each camera's name at the top of its half and the time at the bottom-left of
  the whole, on the same dark strips as today. The renderer loops the paired plan the way it
  loops the single one, fetching up to two images per step.
- **Left and right.** `PopoverMenu` passes the Settings camera's name
  (`CaptureManager.currentVideoCaptureDevice?.localizedName`) as `left`; the plan falls back to
  name order when it isn't in the stretch or isn't given. Tests call the plan directly.
- **Rejected:** holding the last frame in an idle panel (misleading); stacking the panels
  (portrait output, worse on every screen it'll be watched on); a double-width canvas (twice
  the file for a picture nobody views at full size).

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

## Tasks
- [x] `pairedPlan`, the left/right rule and the panel placement, with tests
- [x] The paired drawing and the renderer's second loop
- [x] The menu passes the Settings camera
- [x] Help page sentence (marked, in `site/help`); the changelog entry comes with the release

## Verification
Jake connected a second camera on 2026-10-01, so the look is checked on this Mac.
- **Built (2026-10-01):** `TimeLapse.pairedPlan(events:durations:leftCamera:)`, nil unless the
  recordings name exactly two cameras: the moments are every still step (the first grid step at
  or after a recording's start, on the two-second grid from the earliest start) and every
  sample step a recording covers; at each, a camera shows its still if one starts there, else
  the sample from the latest recording covering it, else nothing. `panelRects` halves the
  canvas; `draw(panels:time:into:canvas:)` letterboxes each picture into its half, names each
  half at its top and puts the time once at the bottom-left, through a shared `drawStrip`.
  The renderer builds a list of drawings from whichever plan applies and writes them through
  the same loop as 0055, the canvas from the first readable picture. The menu passes the
  Settings camera's name as `leftCamera`. Seven tests: the shared timeline with stills at their
  first step and a dark panel before the second camera starts, the Settings camera going left
  and a camera outside the stretch not choosing, one camera having no pairs, a gap neither
  camera covers producing no frame, the halves and a 16:9 picture letterboxed into one, two
  stills of different sizes rendering to two frames at the first one's size, and drawing two
  empty panels. Clean build, 425 tests, no warnings.
- **Checked on this Mac (Jake, 2026-10-01 10:00), two cameras connected:** a stretch with both
  cameras and a one-camera event renders two panels, the Settings camera left, names at the top,
  the time at the bottom-left, the idle panel dark with its name, each still at its recording's
  first step; a one-camera stretch still fills the frame. Help sentence rewritten by Jake and
  its markers struck. `scripts/check` green.

## Open questions
1. Resolved (Jake, 2026-10-01): dark with the camera's name. It says "this camera wasn't
   recording", which is the truth; a held frame would show a still room where none was
   recorded. The panel exists only inside a two-camera stretch: a stretch with one camera's
   files, whatever Settings holds, gets the full frame as in 4.17.
2. Resolved (Jake, 2026-10-01): halves of the first frame's size, so a 1080p stretch makes a
   1080p movie with two 960-wide panels. It's watched in a window and it's the file that gets
   sent; a double-width canvas is twice the file for the same picture. The recordings keep
   full size for anyone who needs a face.
3. Resolved (Jake, 2026-10-01): a second camera is connected, so the two-camera result is a
   manual check here like any other.

## Closure
Shipped in 4.18 (2026-10-01), direct download and the tap (cask `46d6214`, `scripts/check-tap`
green), build 915 uploaded to App Store Connect by the release run and meant for the store's
4.18, which takes the slot 4.16 freed the same morning.
