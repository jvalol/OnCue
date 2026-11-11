---
title: Make OnCue fail on purpose
status: abandoned   # draft → approved → shipped | abandoned
created: 2026-09-21
commits: <filled in as work lands>
---

## Abandoned, 2026-09-21
Not built. Nothing here is wrong, and the seven checks are still unchecked, but building machinery
to run them is work in front of a problem nobody has had yet. The unchecked list already says where
to look if one of them turns out to matter, and that is the signal to come back to this.

Kept rather than deleted because the analysis holds if that day comes: what the seven checks have
in common, why each is hard to produce, and Jake's decision that a switch like this must never
reach a shipped build.

## Problem
Seven manual checks across three specs are on the deliberately unchecked list, and they are all
the same check: does what OnCue says match what OnCue did.

- 0029: the stop threshold saying so, a deletion saying so, the Settings field, an armed session
  with the limit off.
- 0030: sound still watching through an outage, the affected camera's meter greying, a real camera
  recovering.
- 0031: a deletion mid-recording saying so, a long recording rolling and trimming for real.

None of them were skipped out of laziness. Each needs a state that is genuinely hard to produce:
a disk with under 2 GB free, a GPU texture cache that refuses to allocate, hours of continuous
motion against a low limit. Producing them for real costs more than the thing being tested, and
faking them convincingly is harder still.

So the rules underneath have tests and the wiring from those rules to the interface does not, in
exactly the parts of the app that exist to be trusted when nobody is watching. Every one of these
is a place where OnCue could be silently saying the wrong thing, and the only way anyone would find
out is the way the last three bugs were found: by hitting it.

That's the pattern worth naming. The external drive bug, the Time Machine folder, and the stale
Settings label were all found by use rather than by tests, and all three were in this same seam.

## What makes this hard
A switch that makes OnCue misbehave is a switch that can make OnCue misbehave. It would sit in
shipped code, in an app whose whole claim is that it keeps working while nobody is there, and a
stuck or accidentally-set flag is a camera that isn't recording.

That risk is the design problem, not an objection to solving it. It decides where the switch lives,
who can reach it, how it announces itself, and how it clears.

## Non-goals
- Simulating a camera. A fake video source is a much larger thing and it isn't what these seven
  checks need: they need the *failure*, not the footage.
- Automating the checks. This is about making them possible to run by hand in a minute rather than
  impossible. If some can be automated afterwards, good, but that isn't the goal.
- Testing AVFoundation or Metal. OnCue's reaction is what's untested, not theirs.

## Behaviour (acceptance criteria)
- [ ] Each of the seven checks can be produced deliberately, without filling a disk or breaking a
      GPU. Manual check, once per item.
- [ ] Nothing about it is reachable by accident: not a click away, not a preference anyone might
      set, not on by default. Unit test on the rule that enables it.
- [ ] While it's on, OnCue says so somewhere the user cannot miss, because a camera pretending to
      fail must never be mistaken for one that is failing.
- [ ] It cannot survive a restart. Unit test.
- [ ] With it off, every path behaves exactly as it does today. Unit test.
- [ ] `scripts/check` passes.
- [ ] No `[COPY - Jake]` marker remains in shipped copy.

## Design
Nothing settled, but the shape is constrained by what the seven checks need:

- Three states have to be forceable: no room (0029, 0031), motion detection stopped (0030), and a
  write failure (0027's classification, which everything else reports through).
- They are all already funnelled through a small number of methods on `RecordingManager`:
  `noteNoRoom`, `motionDetectionChanged(stopped:)`, `noteOutcome`. The seam exists; what's missing
  is a way to reach it that isn't a real disk filling up.
- The free space read is the cleanest injection point for the disk cases, because
  `DiskBudget.hasRoomToRecord` already takes a number. A forced value there produces the real
  behaviour rather than a simulation of it, which is the difference between testing the wiring and
  testing a mock of it.

## Gates
- [ ] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [ ] All seven checks run, and the deliberately unchecked list shrinks by seven

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

If OnCue is pretending, it has to say so in terms nobody could read as a real fault, and it must be
obvious how to stop.

## Tasks
- [ ] Settle what can be forced and how it's reached
- [ ] The rule for when it's on, with tests
- [ ] Saying it's on
- [ ] Run the seven checks, and shrink the list

## Verification
What was actually checked, filled in as it happens: tests, a run on this Mac, a recording on disk.

## Open questions
1. Largely answered by 2. With the switch absent from shipped builds, how it's reached is a
   question of convenience rather than safety. An environment variable is the obvious candidate:
   it's set where a debug build is launched from, and it dies with the process.

2. Resolved (Jake, 2026-09-21): debug and test builds only. It does not ship.

   That removes the risk in "What makes this hard" completely rather than managing it, and the
   thing given up is smaller than it first looks. What these seven checks exercise is the wiring
   from a rule to what a user sees, and that wiring is the same code in both configurations. Debug
   and Release differ by optimisation and by assertions being live, neither of which changes
   whether the popover says the right sentence or the meter greys.

   Worth knowing rather than worth worrying about: `assertionFailure` does fire in Debug, and
   `MotionDetectMetalRenderer.render` has one on the not-prepared path. Forcing detection to stop
   may trap there rather than showing the release behaviour, so that particular check needs the
   assertion accounted for.

   It also answers questions 1 and 4 almost entirely. With no possibility of the switch existing in
   a shipped build, reachability stops being a safety question and becomes a convenience one, and
   an environment variable clears itself on relaunch by construction.

   One thing this decision should buy that `#if DEBUG` alone does not: proof. `scripts/release`
   already refuses to ship a copy marker; it can refuse just as cheaply to ship a build whose
   binary contains the switch, which turns a compiler directive into a verified absence.

3. What does it force, exactly? Free space is one number and forcing it gets 0029 and 0031 almost
   entirely. Motion detection stopping and a write failure are each a separate hook. Three switches
   or one, and if one, what it means to "fail" when the states aren't alike.

4. Largely answered by 2. An environment variable is gone on the next launch without anything
   having to clear it, and a switch that cannot exist in a shipped build cannot be left on in one.
