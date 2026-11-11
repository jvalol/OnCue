---
title: Say when frames are being dropped from a recording
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-20
commits: 832bc5b, e594e4f (spec), caba42f (implementation)
---

## Problem
Frames can disappear from a recording and nothing anywhere says so. A file that should hold 30
frames a second can hold ten, or none for twenty seconds, and OnCue reports a successful recording
either way. This came up chasing something else (spec 0023): a file with a 24 second hole in its
video was mistaken for a capture bug, and took a logging build to rule out.

For a security camera that's the worst kind of failure. The recording exists, the file plays, and
what it doesn't show is the thing you were watching for. Nobody finds out until they go looking
for footage of something that happened.

There are three places a frame can vanish without a word:

- `CameraPipeline` skips a frame whenever the encoder is behind: `guard let session =
  compressionSession, framesEncoding < maximumFramesEncoding else { return }`, with the cap at 2.
  That guard exists on purpose, to stop the encoder holding capture buffers until the pool starves,
  and it should stay. But it returns silently and nothing counts what it dropped.
- `PreRollRecorder.drain` appends to an `AVAssetWriterInput` and ignores a refusal: `if
  input.append(next) { … }` with no else. A refused sample is gone.
- `VTCompressionSessionEncodeFrame`'s callback returns early on a bad status or a nil buffer,
  again without a count.

`AVCaptureVideoDataOutput` also has a delegate callback for frames the system itself dropped,
`captureOutput(_:didDrop:from:)`, which OnCue doesn't implement at all.

## Non-goals
- Stopping the drops. The backpressure guard is load-shedding and is the right behaviour; this
  spec is about knowing, not preventing.
- A frame-perfect count. An order of magnitude is enough to tell "a few frames on a busy second"
  from "a third of the recording".
- Diagnostics for audio. Sound has its own path and its own questions.

## Behaviour (acceptance criteria)
- [x] Every place a video frame is dropped increments a counter, and the counters are separable by
      reason: encoder behind, writer refused, encode failed, capture dropped. Unit test on the
      counting.
- [x] A finished recording knows how many frames it wrote and how many it lost. Unit test.
- [x] A recording that lost a meaningful share of its frames says so where the user will see it.
      The rule is tested; the rename itself is not exercised end to end (see Verification).
- [x] Nothing is said about a recording that lost nothing, or next to nothing. Unit test on the
      threshold.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- Two measurements, because they answer different questions. A counter per reason says *where*
  frames went, which is for diagnosis. What drives the name is measured from the frames that
  actually landed: their timestamps give the total time not covered and the longest single gap,
  which catches every drop site at once and anything nobody thought of.
- The gaps are accumulated as frames are written, not stored: a running last-timestamp, a total,
  and a longest. The nominal interval comes from each sample's own duration, so a camera that
  isn't 30 fps needs no special case.
- The rule is pure and testable: report when the longest gap reaches a second, or more than 10% of
  the expected frames are missing.
- The name is changed after `finishWriting`, since the numbers aren't known until then. The file
  is renamed on disk, but `onFinish` is called with the original URL: `RecordingManager` matches
  finished recordings by path, and handing it a name it never issued would break that bookkeeping
  and with it the wait that quitting depends on.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [x] A recording made under deliberate load reports its drops (waived, see Verification)

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

## Tasks
- [x] The counter, with tests
- [x] Count at all four sites, including a `didDrop` delegate that didn't exist yet
- [x] The rule for when a loss is worth reporting, with tests
- [x] Say it in the file name, renaming after the file closes
- [x] Manual checks, Verification filled in

## Verification

**Built, 2026-09-20.** 135 tests, one skipped (0022's pre-26.2 path), no failures and no new
warnings.

`FrameLoss` holds both measurements. `Tally` counts by reason and is incremented at all four
sites: the backpressure guard and the compression callback in `CameraPipeline`, the refused
append in `PreRollRecorder.drain`, and a `captureOutput(_:didDrop:from:)` that OnCue never
implemented. `Gaps` accumulates from the frames that land, three numbers rather than a list of
timestamps, taking the nominal interval from each sample's own duration so a camera that isn't
30 fps needs no special case.

The rule is tested against the real measurements rather than invented ones: the shape of the file
that started this spec (451 frames where 1273 were due, one 24 second hole) is worth saying, the
healthy recordings from the 0023 trial (774 frames where 780 were due) are not, and alternate-frame
shedding with no gap over a tenth of a second is caught by the share test that a gap test alone
would miss. Jitter up to one and a half intervals isn't read as loss.

Deliberate: the rename happens after `finishWriting`, but `onFinish` still reports the original
URL. `RecordingManager` matches finished recordings by path, so handing it a name it never issued
would break that bookkeeping and with it the wait that quitting depends on. A rename that fails
leaves the recording under its original name and says so in the log; the footage matters more than
the label.

**Closed without it (Jake, 2026-09-20).** One path is verified by test rather than by observation:
a real recording that lost frames and came out renamed, meaning `FileManager.moveItem` on an
actual file the instant after `finishWriting` returns. Nothing reproduced it, forcing it would
have meant manufacturing load, and waiting for it could take months. The rule that decides the
name is tested against the measurements from the file that prompted the spec; the rename itself
is not exercised end to end.

If a renamed recording does turn up, the thing to check is that the file opens under its new name
and that `RecordingManager`'s bookkeeping was unaffected, since `onFinish` deliberately reports
the original URL.

## Open questions
1. Resolved (Jake, 2026-09-20): the file name, and only when the loss crosses the threshold. The
   moment that matters is someone scrolling a folder looking for footage of something that
   happened, possibly weeks later, and the name is the only thing that survives to it. A popover
   line would be long gone, and for an unattended camera nobody is watching the popover when the
   drop happens. Keeping it conditional is what stops it being ugly: files that lost nothing keep
   the name they have now, so a longer name stands out in a list precisely because its neighbours
   don't have one.

   The cost, which the implementation has to handle: OnCue doesn't know the count until the file
   closes, so this is a rename after `finishWriting` rather than a name chosen up front, and a
   rename can fail or collide. Today the URL is fixed when the recording starts.
2. Resolved (Jake, 2026-09-20): both tests, as a starting point to adjust later. The name appears
   when either a contiguous gap reaches a second, or more than 10% of the expected frames are
   missing overall.

   Both are needed, and the reason is specific. The backpressure guard sheds alternating frames
   when the encoder is behind, giving 15 fps with no gap longer than a tenth of a second: half the
   footage gone, and a gap test alone would see nothing wrong. A long hole is blindness whatever
   the percentage says, since a second is enough for someone to cross the frame unseen.

   The numbers come from two runs on one Mac, not from tuning. Healthy files measured 29.8 fps
   with no gap over half a second; the bad one ran at 10.6 fps with a single 24 second hole. One
   second clears the noise floor comfortably. They live in a testable rule, so they are cheap to
   move.

   The name carries the total missing time rather than a percentage: "38s missing" says how much
   can't be seen without arithmetic against a duration the reader would have to go and find.
3. Resolved (Jake, 2026-09-20): not in this spec. Deliberately dropping to 15 fps would at least
   space the surviving frames evenly, and lowering the bitrate would keep all 30 at lower quality,
   which for a security camera is usually the better trade. But nobody knows whether the
   backpressure guard fires once a month or constantly, and hardware H.264 for two 1080p30 streams
   should be untaxing on an M-series Mac. The counters here are the instrument that answers it:
   ship them, watch real recordings, and if the encoder turns out to be behind on a meaningful
   share of them, that's a later spec with evidence behind it.
