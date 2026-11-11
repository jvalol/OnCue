---
title: Keep the disk promises during a recording, not only between them
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-21
commits: 0b7e9f1 (implementation), 4f2e3f9 (approval), 345034c (released in 4.7)
---

## Problem
Spec 0029 made two promises: OnCue stops before the disk is full, and a rolling window keeps its
own recordings under a limit you set. Both are only kept between recordings.

`startRecording` checks free space once, before opening the file, and `trimToDiskBudget` runs from
`recordingDidFinish` and only when every file has closed. Nothing looks at either while a file is
open.

That would be fine if recordings were short, and they are not bounded at all. A recording keeps
going while activity continues, and the timeout is only how long OnCue waits after activity stops,
up to ten minutes. A curtain in a breeze, a TV left on, or traffic past a window keeps one file
open indefinitely. At roughly a megabyte a second per camera, an eight hour night is about 29 GB
in one file, or 58 GB with two cameras.

So the case where the limit matters most is exactly the case it doesn't cover, and a 20 GB limit
can be exceeded several times over by a single file while OnCue believes it is keeping to it.

## Non-goals
- Deciding what's worth keeping by looking at the footage. Still true from 0029.
- Managing anything OnCue didn't write.
- Ending a recording because activity stopped. That's the timeout's job and it already works.

## Behaviour (acceptance criteria)
- [x] The rolling window is kept to while a recording runs, not only once one finishes. Unit test
      on the rule.
- [x] A recording that would take the folder past the limit rolls into a new file rather than
      carrying on, so the file that just closed becomes deletable like any other. Unit test.
- [x] The roll is taken on a keyframe, so no footage falls between the two files. Unit test.
- [x] Neither file being written is ever deleted, with one camera or two. Unit test.
- [x] Running out of free space during a recording finishes the file cleanly and says so, rather
      than writing until the write fails. Unit test on the rule.
- [x] With the window off, a long recording behaves as it does today, except that the free space
      stop now applies to it. Unit test.
- [~] Deleting during a recording says so the same way deleting after one does. Deliberately
      unchecked.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- The rules are already pure and already take what they need. `DiskBudget.toDelete` takes the
  in-progress paths and `hasRoomToRecord` takes free bytes. Most of this is wiring rather than new
  judgement, plus one new rule for when to roll.
- A 30 second timer on the main queue while `armedState == .recording`, the same shape as spec
  0030's motion health check, stopped when the recording ends so nothing walks the folder while no
  file is growing in it.
- `ownRecordings` reads sizes off disk each time, so the growing file is counted at its current
  size rather than the size it opened at.
- Rolling is a stop and a start on the recorder, taken at a keyframe. `PreRollRecorder` already
  knows which samples are keyframes, since that is how pre-roll picks where a file begins, and the
  ring holds the samples across the writer's 50 to 70ms so nothing has to be caught live.
- Stopping for space finishes the file rather than abandoning it. That is the whole difference
  between a clean stop and a dressed-up failure, and it is what keeps the footage already written.
- Reporting reuses 0027 and 0029: a stop for space is a `.diskFull` failure, and a deletion during
  a recording says what a deletion after one says.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [~] A long recording against a low limit rolls, deletes older recordings, and never its own open
      file, with the two files meeting at a keyframe and no footage between them. Deliberately
      unchecked: hours of real recording for signal the tests already give.

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

Nothing new to say. A stop for space is 0027's "no room left where recordings go", and a deletion
is 0029's line. If either needs different words for happening mid-recording, that's a sign the
existing ones were wrong.

## Tasks
- [x] The rule for when a recording should roll, with tests
- [x] The check while recording, and where it runs
- [x] Rolling on a keyframe, through the recorder
- [x] The free space stop during a recording, finishing the file
- [x] Verification filled in, with what was deliberately left unchecked

## Verification

**Built, 2026-09-21.** 226 tests, one skipped (0022's pre-26.2 path), clean build, no new warnings.

`DiskBudget.shouldRoll` weighs only the files being written, not the folder. Deliberately: once
they alone are over the limit, no amount of deleting around them brings the total under, and asking
about the whole folder would have made the answer depend on whether trimming had already run this
tick. There's a test saying so by name, because the first version of this rule had that bug.

The roll lands on a keyframe inside `PreRollRecorder`, which is the only place that can see one.
`appendVideo` takes the roll before offering the sample to the open writer, so that frame ends up
beginning the new file instead of ending the old one, and the two meet with nothing between them.

The new file opens from `finishIfStopped` rather than where the roll was asked for, because that
is the first moment the old writer is actually nil. Draining can take several passes when an input
isn't ready, and `open` refuses while a writer is still there, so opening any earlier would have
lost the roll silently.

Stopping for space finishes the file. Why it stopped is noted after the files close, not before:
a recording that ends without error clears the last failure, so noting it earlier would have wiped
the reason. There's a test for that ordering.

**Deliberately unchecked, 2026-09-21, by Jake's decision.** Watching a real recording roll takes
hours of footage against a low limit, for signal the unit tests already give. Not worth the effort,
and a bridge to cross if it ever shows up in use rather than something to chase now.

- Deleting during a recording says so the way deleting after one does.
- A long recording against a low limit rolls, trims, and never its own open file.

**Shipped in 4.7, 2026-09-21,** build 850. Verified from the public URL: the download matches the
repo's zip by SHA-256, the staple validates, and Gatekeeper accepts it offline.

## Open questions
1. Resolved (Jake, 2026-09-21): every 30 seconds, only while `armedState == .recording`.

   Both things being guarded have large slack. At about a megabyte a second per camera, half a
   minute late is at most 60 MB of overshoot with two cameras: 3% of the 2 GB free space headroom,
   6% of the smallest limit anyone can set. Neither changes an outcome.

   Faster costs more than it buys, since the check walks the recordings folder and stats every file,
   in the folder the recording is being written to. Much slower starts to matter for the free space
   stop: 2 GB is about a thousand seconds of slack at two cameras, so a five minute check would
   spend a third of the margin between looks.

2. Resolved (Jake, 2026-09-21): roll into a new file rather than letting it run.

   0029 chose to do nothing here, and that was right for what it was looking at: a finished file,
   where deleting everything else wouldn't bring the total under and would destroy footage for no
   gain. A file still growing is different. Nothing stops it, and doing nothing means the limit
   quietly stops being true for as long as the event lasts, which is exactly when someone would go
   looking.

   Rolling makes it true again: the recording continues in a new file, the one that just closed is
   deletable like any other, and a long event under a 20 GB limit leaves roughly the most recent
   20 GB. It costs what segmenting costs, which is more than one file for one event, but only when
   the limit is smaller than the event, which is the user asking for this trade.

   No thrash at real settings. At a megabyte a second, a 1 GB limit rolls every seventeen minutes
   with one camera and eight with two, and the limit is in whole GB so there's no tighter setting.

3. Resolved (Jake, 2026-09-21): yes, and it finishes the file rather than abandoning it.

   The framing in the first draft was wrong. Stopping mid-recording is not giving up at the moment
   something is happening, because the alternative is not carrying on successfully. It is writing
   until the write fails: a few more seconds, a lost tail, 0027's yellow icon afterwards, and a Mac
   with no free space, which hurts everything else on it and stops OnCue recording the next thing
   too.

   Stopping at the headroom keeps every second already written, says so the way a failed recording
   does, and leaves room to start again. With the window on, trimming can then free space and OnCue
   carries on watching.

4. Resolved (Jake, 2026-09-21): no time cap.

   The seam was measured first, and it is zero when the roll is taken on a keyframe. Finishing a
   file takes 43 to 60ms and does not scale with size, because `movieFragmentInterval` writes the
   index as it goes: an 812 MB file finished faster than a 164 MB one. The next writer is ready in
   about 8ms. Nothing is lost across that, because `appendVideo` puts every sample in the ring
   before offering it to the writer and the ring holds seconds.

   What would cost footage is where a new file may start. A file has to begin at a keyframe and
   `kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration` is 1.0, so a roll at an arbitrary moment
   loses up to a second. Taking it on a keyframe removes that: the frame that ends one file begins
   the next.

   With that measured, the objection to segmenting was gone, and the question stood on whether a
   time cap earns its place. It doesn't. Question 2's size roll bounds the file whenever the window
   is on, and question 3's clean stop protects the disk when it's off. All a time cap would add is
   avoiding a single large file on a night with no limit set, which is not worth a second mechanism
   with its own rules.
