---
title: Say when motion detection stops working
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-21
commits: d2d314a (implementation), 6cddf46 (approval)
---

## Problem
Motion detection can stop working while OnCue carries on looking perfectly normal. The menu bar
icon stays as it was, Arm stays offered, the popover says armed, and nothing ever records.

`CameraPipeline` prepares the Metal renderer when it isn't ready and then renders each frame. If
either fails, `render` returns nil, the pipeline prints "Unable to filter video buffer" and
returns. `measuredMotion` is only delivered on success, so the popover's motion meter simply stops
being updated and holds whatever it last showed. Nobody reads the log on a machine left watching a
room.

Three ways it happens today: the texture cache fails to allocate, the output pixel buffer pool
can't be made because the format isn't 32BGRA, or the compute pipeline state failed to build at
launch. The first is transient and now retried every frame (commit 7862544). The other two are
permanent for the life of the session.

This is the same failure shape spec 0027 fixed for recordings, in the one place it matters more:
0027 tells you footage was lost, and this would tell you footage is not being taken at all.

## Non-goals
- Making motion detection work on formats or hardware where it can't. This is about saying so.
- A CPU fallback for the frame diff.
- Audio. It's measured on the CPU with no GPU path and no equivalent failure.
- Deciding what a camera *should* see. A camera pointed at a wall measures no motion, correctly,
  and that is not this.

## Behaviour (acceptance criteria)
- [x] Five seconds without a measurement, while capture should be running, counts as stopped.
      Less does not. Unit test.
- [x] A camera that is simply seeing nothing is never reported as stopped: it is measuring, and
      reporting a level of zero. Unit test.
- [x] A camera OnCue has released on purpose (spec 0023) is never reported as stopped. Unit test.
- [x] The warning clears as soon as measuring resumes. Unit test.
- [x] An outage that ends leaves behind the same "wasn't watching" gap the popover already shows
      after the Mac sleeps, and that stays until disarm. Unit test.
- [x] Arm is refused while motion is the only trigger and detection has stopped, and offered again
      when it recovers. Unit test.
- [x] An OnCue that is already armed stays armed through an outage, and resumes watching when
      measuring returns. Unit test.
- [~] Sound keeps watching and recording throughout. Deliberately unchecked.
- [~] The affected camera's meter is greyed while nothing is measuring, and its threshold slider
      still works. Deliberately unchecked.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- A pure rule in `Managers/Helpers/`, taking the time since the last successful measurement and
  whether capture should be running at all, returning whether motion detection is working. Keeping
  it pure is what makes the "camera sees nothing" case testable, since that camera is still
  measuring and still reporting a level of zero.
- The report goes through what 0027 already built: `RecordingManager` holds the state, the menu bar
  icon has a warning appearance, and `PopoverNotice` picks what the notice line says.
- `PopoverNotice` gains one live case, not a second past-event one. A live problem outranks
  everything else there, since the other cases are all news about things that already finished and
  this one is still happening. The outage's aftermath reuses `wasNotWatching`, which is already
  ordered against the rest.
- `CameraPipeline` already knows when a render fails. The signal is a timestamp of the last
  successful `measuredMotion`, not a counter: frame rates vary, and a second of no measurement
  means the same thing at 15fps and 60fps.
- Rejected: reporting it as `cameraAvailable = false`. That reuses existing arming logic neatly,
  but it would say the camera is gone when it's plugged in and lit, and the preview would keep
  showing its picture. Lying in a way the user can see through is worse than a new state.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [~] A real camera, detection broken on purpose, reports it and recovers. Deliberately
      unchecked: breaking a GPU texture cache on demand isn't something to fake convincingly.

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

The notice must say that motion isn't being watched right now, not that the camera is missing, and
must not imply recordings failed. If sound is still armed it should be clear that OnCue is still
watching by sound.

## Tasks
- [x] The rule for when detection counts as stopped, with tests
- [x] The timestamp of the last successful measurement, through the pipeline
- [x] Where it's said: notice line and the meter
- [x] Verification filled in, with what was deliberately left unchecked

## Open questions
1. Resolved (Jake, 2026-09-21): five seconds without a measurement, and only while capture should
   be running.

   The floor is set by stalls that are not failures. A texture cache that fails recovers on the
   next frame, and capture warm-up was measured this session at 856ms cold and 350 to 370ms warm,
   so a camera switch can go most of a second with nothing measured while working perfectly.

   The ceiling is set by who is looking. Someone who just armed it is still at their Mac for a few
   seconds, and that is the only moment anyone is likely to see this while it still matters. Five
   is clear of every legitimate stall and is already the app's human unit, the Arm countdown.

2. Resolved (Jake, 2026-09-21): a live warning that clears on recovery, leaving a gap notice
   behind.

   The two halves are different claims. "Motion isn't being watched right now" stops being true
   the moment it is, so it clears. But an outage that lasted three minutes means three minutes
   went unwatched, and that stays true: it is the same news as 0024's dropped frames and 0027's
   failed recordings, which is that you have less footage than you think.

   OnCue already says exactly that. `wasNotWatching(from:to:)` is what the popover shows after the
   Mac sleeps while armed, and it stays until disarm. A detection outage is that sentence with a
   different cause, so `PopoverNotice` gains one live state rather than a second past-event case
   that would need ordering against the three already there.

3. Resolved (Jake, 2026-09-21): refuse Arm, consistent with a missing camera.

   OnCue already refuses to arm when motion is the only trigger and the camera is gone. From where
   the user stands, "camera gone" and "camera there but nothing measuring it" are the same: press
   Arm, watch the countdown, and nothing will ever record. Arming when nothing can fire is the lie
   this spec exists to stop, and the worst version of it, because the person walks away believing
   they are covered.

   It un-refuses by itself, since `canArm` is re-evaluated as state changes.

   The risk, named because it is the largest in this spec: a false reading blocks arming, which is
   worse than a spurious warning. Two things hold it down. The rule only applies while capture
   should be running, and the popover is open while someone is deciding to arm, so OnCue has had
   frames and is not guessing. And the live warning is right there, so a refused Arm is never
   unexplained.

4. Resolved (Jake, 2026-09-21): no, an armed OnCue stays armed. Deliberately the opposite of 3.

   Refusing to Arm happens while you are standing there and can act. Disarming happens after you
   have walked away, and nobody is there to undo it. If detection breaks at second five and
   recovers at second seven, a self-disarming OnCue is unarmed for the whole night with nothing to
   say so.

   Staying armed costs nothing, since nothing would have recorded during the outage anyway, and it
   resumes the instant measuring resumes. It also matches the app: 0027 chose to keep watching
   through trouble, and a sleep gap is reported rather than acted on.

5. Resolved (Jake, 2026-09-21): grey the meter out, meaning disabled.

   Zero is the trap, and worse than the stale value it would replace. A threshold-coloured meter
   sitting at zero looks exactly like a working camera watching a still room, which for a security
   camera is the most misleading thing the interface could show, because it is the picture of
   everything being fine. Holding the last value is today's behaviour and false in a quieter way.

   Disabled is the macOS idiom for "not reflecting anything right now", is distinct from any real
   level, and needs no new copy. The threshold slider stays enabled, since the setting still
   matters for when detection returns.

   The renderer is per camera, so with two cameras only the broken one greys, which says which
   camera stopped.
