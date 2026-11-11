---
title: Say what the trigger is costing
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-21
commits: cad02ba (implementation), 5309661 (approval), 345034c (released in 4.7)
---

## Problem
A recordings folder fills because of how often OnCue records, not how big each recording is, and
OnCue never says so.

Two days of light testing made 297 files and 5.5 GB, averaging 18.8 MB. At roughly a megabyte a
second that's about 19 seconds each, against a floor of about 10 seconds for a single brief
trigger: five of pre-roll plus five of waiting after movement stops. The typical recording is
barely above the shortest one OnCue can make, which is the signature of a threshold catching things
that don't matter.

The control for that already exists. The popover has a slider, a live meter, and 0025's colour
bands showing what would and wouldn't fire. What's missing is any feedback on what the setting is
actually producing once you walk away. You would only find out by opening the folder and counting.

That gap is the odd one out in this app. Dropped frames, failed recordings, deletions, detection
stopping: OnCue learned to say each of those out loud precisely because they are invisible
otherwise. A threshold quietly recording 150 times a day is the same shape, and it's upstream of
the thing 0029 and 0031 exist to clean up after.

## Non-goals
- Changing the threshold for anyone. OnCue doesn't get to decide what matters in a room it can't
  interpret.
- Judging the footage. Still true from 0029: OnCue knows when a recording happened and how big it
  is, and nothing about what's in it.
- A statistics window. This is a line, not a dashboard.

## Behaviour (acceptance criteria)
- [x] OnCue says how many recordings it made in the last 24 hours and how long they typically run.
      Unit test on the rule.
- [x] It says nothing until there are enough recordings in the window for a typical value to mean
      anything, so a fresh install and a quiet day are both silent. Unit test.
- [x] Silence is never OnCue approving of anything: the condition is whether the statement would be
      true, not whether it looks good. Unit test on the boundary.
- [x] It counts only recordings OnCue wrote, never anything else in the folder. Unit test.
- [x] The shortest recording OnCue can make is legible alongside the typical one, so the comparison
      lands without OnCue drawing it. Unit test on the rule.
- [ ] It sits on its own line in the popover, not the notice line, and shows armed or not. Manual
      check.
- [x] `scripts/check` passes.
- [ ] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- `FileOutputManager.ownRecordings()` already answers this: it gives OnCue's own files with their
  start times and sizes, and refuses everything else, which spec 0029 tested against a real folder.
- Duration doesn't need reading out of the files. At a fixed 8 Mbit/s a megabyte is about a second,
  so size is a good enough proxy, and it's already in hand. That's a small consolation prize from
  the fixed bitrate that killed spec 0032.
- The rule is pure: recordings in, a summary out. Which keeps the judgement about what's worth
  saying testable, and out of the view layer.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

The line must read as information rather than a telling-off, and must not imply OnCue knows whether
those recordings were worth making. It should make the connection to the slider without instructing
anyone to move it.

## Tasks
- [x] The rule for what to say, with tests
- [x] Where it's said
- [ ] Manual check, Verification filled in

## Verification

**Built, 2026-09-21.** 236 tests, one skipped (0022's pre-26.2 path), clean build, no new warnings.

`TriggerCost` holds the rule. It reports a median rather than a mean, because one long event would
drag a mean away from what the folder is actually full of, and the whole point is describing the
typical recording.

The floor is tested from both sides, at nine and at ten, because the thing that makes it honest is
that it's a floor on whether a typical means anything and not on whether the number flatters the
setting. There's a test named for a busy day being reported rather than judged.

A recording dated in the future is excluded, which matters because clock skew can produce one (see
the note in project memory) and it would otherwise sit in the window dragging the typical around.

`assumedBitsPerSecond` moved out of `CameraPipeline` and into `TriggerCost`, because this is the
code that depends on it being fixed: reading a length back out of a size only works while every
second costs the same. `CameraPipeline` now sets the encoder from it, so the two cannot drift.

The line sits under the arm state on its own, and the popover grows by its height the way it
already does for the second camera and the Edge Light warning.

**Shipped in 4.7, 2026-09-21,** build 850. Verified from the public URL, alongside spec 0031: the
two are the same idea from both ends, one keeping the limit true while a recording runs and the
other making the limit less likely to be reached at all.

## Open questions
1. Resolved (Jake, 2026-09-21): the last 24 hours.

   A session is the more honest unit in principle, one set of settings doing one job, but the
   moment anyone reads this is when they come back and open the popover, which is often after
   disarming. A session number either vanishes then or refers to a session that ended at some point
   they have to remember. 24 hours always means the same thing, survives disarm, needs no state
   between launches, and matches the unit of the thing being diagnosed, which is a night. "Today"
   is worse: at nine in the morning it is nearly empty and says nothing when it should.

   The cost, and there is no way out of it: a 24 hour window contains any change to the slider made
   during it, and reads as one thing. Any window long enough to be meaningful has that problem, and
   tracking "since you last touched the slider" adds persistent state to save one edge case.

2. Resolved (Jake, 2026-09-21): its own line in the popover, not the notice line.

   The notice line is for what is wrong or already went wrong. This is ambient information about a
   setting working as configured, and putting it there would either suppress a real warning or be
   suppressed by one. Spec 0022 made the same call for the Edge Light warning, for the same reason.

   Unlike Edge Light it can't live in the Motion column, because recordings come from either
   trigger and a per-column position would read as "motion caused these". It goes under the arm
   state, where it is about the whole thing. Settings is ruled out: it has room, and it is the one
   place the slider isn't.

3. Resolved (Jake, 2026-09-21): report the shape, don't draw the conclusion.

   The tension in the draft was false, and what dissolves it is what the statement is about. "Most
   of these were probably nothing" is a claim about a room OnCue can't see. "Most of these were
   about as short as OnCue can make one" is a claim about OnCue: it knows how long its own
   recordings were, and it knows its own floor, because the floor is pre-roll plus the timeout and
   the user set both.

   So it says the count and the typical length, and makes the floor legible enough that the
   comparison lands. The reader supplies what OnCue lacks, which is whether an 11 second event at
   their door is a delivery or a branch. That is the voice the app already has: 0024 says how many
   seconds are missing, 0027 how many failed in a row, 0029 how many were deleted, and not one of
   them says what to do about it.

4. Resolved (Jake, 2026-09-21): always, once the number means something.

   Two facts aren't nagging, so there is no reason to hide them when things look fine, and "fine"
   is a judgement question 3 ruled out. The floor is a different kind: a typical computed from three
   recordings is noise wearing a number's clothes, so the line appears once there are enough for the
   statement to be worth making, around ten.

   That condition is about whether the statement would be true, not whether it is flattering, which
   is what keeps OnCue out of judging. A quiet day showing nothing is not approval, it is not having
   enough to say.

   Shown armed or not, like the lid warning, since the window doesn't care about arm state and the
   moment someone is deciding where to put the slider is usually before arming. The wallpaper risk
   is real and worth accepting: being ignored is much cheaper than OnCue deciding a camera is too
   sensitive.
