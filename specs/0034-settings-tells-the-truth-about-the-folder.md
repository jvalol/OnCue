---
title: Make Settings tell the truth about the recordings folder
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-21
commits: d592376 (implementation), 0bcd189 (approval), e020d78 (released in 4.7.1)
---

## Problem
Three things about the folder row in Settings are wrong, and they were all found in one sitting by
using it rather than by reading it.

**It accepts folders it can never write to.** A Time Machine destination was chosen and OnCue said
nothing. Confirmed on the drive in question: `tmutil destinationinfo` lists it, the volume root is
`root:wheel drwxrwxr-x` with the user not in `wheel`, and creating anything there fails with
"Operation not permitted". Recordings then failed while armed, and the only report was 0027's
notice after the fact. The panel had everything it needed at the moment of choosing, when someone
is standing there able to pick somewhere else.

**It goes stale.** `showRecordingsFolder()` runs from `viewDidLoad`, Choose, and Reset, and nowhere
else. The settings window controller is a `lazy var`, so the view loads once per app session and
reopening the window doesn't reload it. Eject the drive and Settings keeps naming it, through a
close and reopen. The fallback note that would have explained it, "The folder you chose isn't
available, so recordings are going here for now", exists and is correctly worded, and never gets
recomputed. Meanwhile recordings really were going to `~/Movies/OnCue`, because the recording path
re-reads the folder each time (spec 0031). The behaviour was right and the display lied about it.

**It doesn't say what the path is.** The row is a bare path, a Choose button and a Reset button,
with no words saying that this is where recordings are saved. It reads as a setting whose meaning
you have to already know.

## Non-goals
- Managing Time Machine, or any other volume's policy. OnCue's job is to find out whether it can
  write, not to explain why it can't.
- Guaranteeing a folder stays writable. A drive can be unplugged a second after it's chosen. This
  is about not accepting something already known to be impossible.
- Changing where recordings go when the chosen folder is unavailable. The fallback works and
  spec 0017 settled it.

## Behaviour (acceptance criteria)
- [x] Choosing a folder OnCue can't write to is refused at the panel, and the folder already in use
      is kept rather than cleared. Unit test on the rule, and Jake saw the refusal.
- [x] The test is a real write, so it catches whatever the reason is rather than guessing at
      causes. Unit test against a real unwritable folder.
- [x] Settings shows the truth every time it's opened, not only the first time in a session.
      Jake checked it.
- [x] The row distinguishes three states: in use, fallen back with the chosen folder named, and
      present but not writable. Unit test on the rule that picks them.
- [x] The row says what the path is. Jake checked it.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- The writability test is a create-and-delete in the chosen folder. That's the only check that
  answers the real question, because permissions, ownership, read-only mounts and Time Machine
  protection all fail differently and all fail the same way when you actually try.
- The refresh is `viewWillAppear`, which runs every time the window is shown, unlike `viewDidLoad`.
  Whatever else this spec does, that one line is the fix for the stale label.
- `RecordingsFolder.current()` already returns `isFallback`, and `showRecordingsFolder` already
  renders it. Nothing new is needed to say it, only to say it again.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [x] A Time Machine volume is refused at the panel, and an ejected drive shows as fallen back

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

The row needs words saying this is where recordings are saved. A refusal must say OnCue can't write
there without pretending to know why, and must not read as the drive being broken, because a Time
Machine disk is working exactly as intended.

## Tasks
- [x] The writability test, with tests
- [x] Refresh when the window is shown
- [x] What the row says
- [x] Manual checks, Verification filled in

## Verification
What was actually checked, filled in as it happens: tests, a run on this Mac, a recording on disk.

**Shipped in 4.7.1, 2026-09-21,** build 852. Verified from the public URL: SHA-256 matches, the
staple validates, Gatekeeper accepts it offline, and the published cask agrees with the published
zip.

**Verified by Jake, 2026-09-21.** The panel refuses a folder OnCue can't write to, Settings shows
the truth on every open rather than only the first of a session, and the row says what the path is.
The unwritable case is also covered by a test that creates a real 0500 directory, which is the same
path a Time Machine volume takes.

Nothing in this spec is on the deliberately unchecked list. That is worth noting against 0029, 0030
and 0031, which are all there for the same reason: their failure states are hard to produce on
demand. This one's were sitting on the desk already.

## Open questions
1. Resolved (Jake, 2026-09-21): refuse it.

   The test is a real write, so it is accurate about the moment it runs, and that is the moment
   that matters: the panel only offers folders that exist and are mounted now, so "it might be
   writable later" can't really arise. Accepting a folder OnCue has just proven it cannot use means
   arming into a guaranteed failure that surfaces later, to someone who has left, which is the
   shape the whole app is built to avoid.

   Refusing is cheap here in a way it usually isn't: the panel is open and the person is standing
   there. The folder already in use is kept rather than cleared, so a refused attempt leaves things
   where they were, and the message says OnCue can't write there without guessing why. It cannot
   tell Time Machine protection from ownership from a read-only mount, and calling a working Time
   Machine disk broken would be worse than saying nothing.

2. Resolved (Jake, 2026-09-21): the Settings refresh, and not arming.

   The refresh is happening anyway for question 3, so testing there costs one write per window open
   and makes the row true every time it is shown rather than only when chosen.

   Arming is left alone because `canArm` is not called once when someone looks at the button: it
   runs from the observers and from `disarmIfNothingCanTrigger` on every `UserDefaults` change. A
   create-and-delete behind that would be hot, and a strange thing to do on a preference write.

   What remains uncovered is narrow: a folder present but unwritable, between opening Settings and
   the next recording. That is reported rather than prevented, by 0027, which is the trade the app
   already makes everywhere else.

3. Resolved (Jake, 2026-09-21): show all three states.

   The folder in use is the primary fact, because "where do my recordings go" is the question the
   row exists to answer, and in normal operation it is one line.

   When they differ, the chosen folder is named, because without it you cannot tell whether to plug
   a drive back in or press Reset. Today's note says "the folder you chose isn't available" without
   saying which, at exactly the moment that matters.

   The third state is the one this spec came from: chosen folder present, and unwritable.
   `current()` treats it as available because it is reachable, so nothing falls back and recordings
   fail. Without question 2's write test it looks identical to normal, which is why the row said
   nothing was wrong while recordings were failing on a Time Machine volume.

4. Resolved (Jake, 2026-09-21): nothing about synced folders, and it stays in the help.

   0029 decided OnCue can't reliably detect one and shouldn't guess, and the reason holds: iCloud
   Drive exposes ubiquity resource keys, Dropbox and Google Drive expose nothing dependable, and a
   warning that appears for one and not the others implies OnCue checked and found nothing. That is
   a stronger claim than silence.

   It is also conditional on something off by default. A synced folder only matters because
   deleting propagates, and OnCue only deletes when the GB limit is set. At 0 it is harmless, and
   arguably good, since the footage ends up somewhere other than the Mac that might be taken.
