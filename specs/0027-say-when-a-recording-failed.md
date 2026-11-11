---
title: Say when a recording failed
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-20
commits: e9a9dcc (spec), 8bd5fed (implementation)
---

## Problem
A recording that fails is reported to a console nobody is reading. `recordingDidFinish` prints the
error and carries on; the menu bar icon stays red, the popover says Recording, and nothing on
screen is any different from a recording that worked.

For an unattended security camera that's the worst shape of failure, and it's the same one spec
0024 addressed a layer down. There the frames were missing from a file that existed; here there is
no file, and OnCue still looks like it's doing its job. You find out when you go looking for
footage of something that happened.

Three ways it happens, none of them exotic:

- **The disk fills.** Nothing in OnCue manages disk use: no retention, no cleanup, no free-space
  check. Measured from this session's own recordings, a camera costs about 1 MB per second while
  recording, so two cameras on a busy night can run to tens of GB. The only file OnCue ever
  deletes is an empty one it just failed to write.
- **The folder goes.** Spec 0017 lets recordings go to any folder, including one on another disk
  or one that syncs. `RecordingsFolder` falls back to Movies when it's missing at the time of
  asking, but an unplugged drive mid-recording is a failed write.
- **Permission changes.** The folder is reached through a security-scoped bookmark, which can stop
  resolving.

## Non-goals
- Managing disk use. A retention rule is a separate question, and a harder one: what a security
  camera is allowed to delete on its own needs deciding, not assuming. This spec is about knowing.
- Retrying, or recording somewhere else instead. Both are decisions about what OnCue does on your
  behalf while you're not there.
- Errors that aren't about writing a recording. Device trouble already has its own handling.

## Behaviour (acceptance criteria)
- [x] A recording that fails to write says so where it will be seen, and says why in terms a
      person can act on. Unit test on the rule, plus a manual check with a full or missing
      destination.
- [x] A recording that worked says nothing, as now. Unit test.
- [x] Both cameras failing says it once rather than twice. Unit test.
- [x] Whatever is said survives until it's seen, rather than clearing on the next trigger. Manual
      check.
- [x] OnCue keeps watching after a failed recording, rather than disarming or stopping. Manual
      check.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- The failure already arrives in one place: `recordingDidFinish(url:error:)` in
  `RecordingManager`, which today prints and moves on. What's missing is anywhere for it to go.
- Turning an `Error` into something worth saying is a pure function, so the cases that matter can
  be told apart from the ones that don't: a full disk, a missing folder and a permissions failure
  read differently and suggest different things, while the rest can share a plain sentence.
- `PreRollRecorder.finishIfStopped` also synthesises an `AVError.noDataCaptured` when nothing was
  ever written, which is a different thing from a write that failed and shouldn't read the same.
- The menu bar icon gains a state for it, alongside the arm states spec 0014 gave it, and the
  detail goes in the popover's notice line. `PopoverNotice.notice` already decides that line from
  pure inputs, so the third claimant and its order live there with the other two.
- The consecutive count is one integer on `RecordingManager`, reset on a success or on disarm, and
  it feeds the same rule that chooses the wording.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [x] A recording aimed at a full or unplugged destination says so, and OnCue is still armed
      afterwards

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

## Tasks
- [x] The rule turning a failure into what to say, with tests
- [x] Somewhere for it to go: the icon, and the notice line
- [x] Keep it until it's seen
- [x] Manual checks, Verification filled in

## Verification

**Built, 2026-09-20.** `scripts/check` passes: 156 tests, one skipped (0022's pre-26.2 path), no
new warnings.

`RecordingFailure.from` reads the cause rather than the error it's handed, which matters because
AVFoundation wraps it: the outer error only ever says the operation couldn't be completed, so
reading that would have made every failure read the same. It follows `NSUnderlyingErrorKey` down
to the POSIX or Cocoa error that says whether the disk is full, the folder is gone, or permission
was refused. Tested through both domains and for the wrapped case.

`isWorthSaying` keeps one thing quiet on purpose: `finishIfStopped` synthesises an
`AVError.noDataCaptured` when nothing was ever captured, which is not a failure to write. The
empty file is already gone and nothing was lost.

`PopoverNotice` gained the third claimant and the order from question 1. Its existing tests pass
unchanged, and new ones cover a failure outranking the lid warning, the more recent of a gap and a
failure winning, and a failure with no count saying nothing.

`MenuBarIcon.appearance` takes a `recordingFailed` flag that overrides the arm state colours.
`RecordingManager` keeps what failed, how many in a row, and when, clearing all three on disarm
beside the sleep gap it sits next to. Both cameras failing counts once, since the second file's
failure arrives while the first is still in `currentFilePaths`.

**Manual check, 2026-09-20.** A failed recording reports itself, OnCue stays armed rather than
stopping, and the message is still there after a later trigger rather than being cleared by it.
Those last two are the ones that matter on a Mac nobody is watching: a security camera that quits
or forgets is worse than one that keeps going and says what happened.

## Open questions
1. Resolved (Jake, 2026-09-20): the menu bar icon says something is wrong, the popover's notice
   line says what. No notification.

   Unlike spec 0024, nothing survives to the moment of discovery: there is no file to carry the
   message, so the app is the only place this can ever be said. The person has been away, and the
   menu bar is the only surface that reaches them without an action, which is why the icon has to
   carry something. It can only be a colour or a shape though, and "the disk is full" and "the
   drive you chose is unplugged" need different responses, so the detail goes in the popover.

   A notification was rejected for more than friction: it fires once, while nobody is there, and
   then it's gone. This has to still be visible when someone walks back in.

   Two costs, accepted. Spec 0014 made the icon's colours mean the arm state and nothing else, and
   this adds a meaning across that. And the notice line gains a third claimant, so it needs an
   order: a failed recording outranks the lid warning, which is a risk that hasn't happened, and
   ties with the sleep gap, which is the same class of "you have less footage than you think", so
   between those two the more recent wins rather than a fixed rank.
2. Resolved (Jake, 2026-09-20): until disarm, the same rule the sleep gap already uses. Disarm is
   the one moment someone is definitely present and acting, which makes it the acknowledgement,
   and it needs no new concept.

   Clearing on the next trigger was rejected because a full disk fails every recording, so that
   would be no better than the print statement this replaces. Clearing on the next *successful*
   recording was rejected too: the condition resolving doesn't unlose the footage, and the person
   still hasn't been told.

   Edge case, accepted: with arm at login and a Mac that's never manually disarmed, this stays
   indefinitely, and the icon sits in its failure state until someone acts. That's correct in that
   nobody has acknowledged it. If it turns out to feel wrong, the fix is a dismissal rather than a
   timeout, since a timeout would delete the only record that it happened.
3. Resolved (Jake, 2026-09-20): count the consecutive failures and let the message say how many.
   Nothing more. One failure is bad luck and ten in a row is a broken setup, and those want
   different responses from the reader; the count is what tells them apart. It costs one integer,
   reset on a success or on disarm, passed into the same rule that decides the wording.

   Acting on it stays out. Disarming after so many failures is the obvious next step and it's
   wrong: a security camera that switches itself off because it hit trouble is worse than one that
   keeps trying and says so, and nothing inside the app can tell whether the cause is permanent.

   The count has a second use. Like 0024's counters, which exist partly to find out whether
   adaptive encoding is ever needed, this answers the same kind of question for the retention spec
   deliberately deferred above: if failures pile up in real use, that's evidence disk management is
   required rather than a theory about it.
