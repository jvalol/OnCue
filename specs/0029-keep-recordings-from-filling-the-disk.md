---
title: Keep recordings from filling the disk
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-20
commits: d3f6cec (implementation), 90ba8dc (approval), d9f5219 (folder-scan test), 1b1d355 (what was checked), 5380fa3 (released in 4.5)
---

## Problem
Nothing in OnCue manages disk use. There is no retention, no cleanup, and no free-space check, and
the only file it ever deletes is an empty one it just failed to write. Left armed, it writes until
the disk is full and then stops being a security camera.

The numbers are not theoretical. Two days of light testing in one session produced 297 files and
5.5 GB, averaging 18.8 MB each, and that was with someone present the whole time. Recording costs
about 1 MB per second per camera, so two cameras through an eight-hour night with a curtain moving
is tens of GB.

Spec 0027 was deliberately scoped to telling you this happened. It turns the icon yellow once the
disk is full, which is the right thing to do and not a substitute for not filling it.

## What makes this hard
Every other spec in this repo adds something OnCue says or notices. This one deletes recordings,
unsupervised, from a security camera. A rule that's slightly too eager destroys the footage
someone installed OnCue to get, and they find out weeks later when they go looking for it.

That asymmetry should shape the whole design: being wrong in one direction costs disk space, and
being wrong in the other costs the only copy of something that happened.

## Non-goals
- Deciding what's worth keeping by looking at the footage. OnCue knows when a recording happened
  and how big it is, and nothing about what's in it.
- Managing anything OnCue didn't write.
- Moving or compressing old recordings. This is about how much disk gets used, not about fitting
  more in.

## Behaviour (acceptance criteria)
- [x] OnCue never fills the disk it records to: it stops before there's none left, or makes room
      if a rolling window is switched on. Unit test on the rule.
- [~] Stopping for lack of space says so the way a failed recording does, rather than looking like
      nothing happened. Deliberately unchecked.
- [x] Whatever it deletes, it deletes oldest first. Unit test.
- [x] It never deletes a recording it is currently writing. Unit test. (Older recordings from
      this session are deletable; the window is about total size, not about when OnCue started.)
- [x] Nothing OnCue didn't write is ever offered for deletion, scanning a real folder holding
      both. Unit test, standing in for the manual check.
- [~] Nothing is deleted without the user having asked for the behaviour. Rule unit tested; the
      Settings default deliberately unchecked.
- [~] Deleting says so somewhere, so footage never disappears silently. Deliberately unchecked.
- [~] With the setting off, behaviour is exactly as it is today, including 0027's warning when
      the disk does fill. Deliberately unchecked.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- The rule is pure: given the recordings OnCue knows about, their dates and sizes, the free space,
  and the setting, it returns what to delete. That keeps every judgement testable and leaves the
  file system out of the decision.
- `RecordingsFolder.current()` answers where recordings go, and a name parsed as one OnCue would
  have written answers which files are its own. Everything else in that folder is somebody else's,
  including a recording the user renamed, which is how "keep this" works without any UI.
- A free-space check is cheap: `URLResourceKey.volumeAvailableCapacityForImportantUsageKey` on the
  recordings folder, read when a recording is about to start rather than continuously.
- Whatever is deleted needs saying, and 0027 just built the place to say it: the popover's notice
  line, with the icon carrying that something happened.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [x] A folder taken to its limit behaves as the setting says, with nothing unexpected deleted
      (by test on a real folder, not by hand)

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

## Tasks
- [x] The rule for what to delete, with tests
- [x] Free space and the recordings OnCue knows about
- [x] The rolling window setting, off by default; the stop threshold isn't a setting
- [x] Say what was deleted
- [x] Manual checks skipped by Jake, Verification says what that leaves unproven

## Verification

**Built, 2026-09-20.** 175 tests, one skipped (0022's pre-26.2 path), clean build, no new
warnings. The storyboard compiles with no ambiguity notices after gaining a row.

`DiskBudget` holds both rules. `hasRoomToRecord` is the stop, with 2 GB of headroom, chosen
conservatively because a recording lasts as long as the activity does and the next one's size is
unknowable. `toDelete` is the window: nothing without a limit, nothing under it, oldest first, and
only as many as it takes to get back under.

The file recogniser is the part that could do real damage, so it's tested against the case that
prompted it. Jake had recordings going to `~/Downloads` during this session, and
`FileOutputManager.recordingDate` refuses screenshots, PDFs, zips, and anything whose name doesn't
start with OnCue's own timestamp format. It accepts 0024's missing-seconds suffix, since that's
still OnCue's file.

Renaming a recording protects it, and there's a test saying so by name, so nobody later makes the
matching cleverer and quietly breaks the only "keep this" gesture there is.

The recording in progress is never offered up, and if it alone is over the limit nothing is
deleted at all: emptying the folder wouldn't bring the total under, so it would destroy footage
for nothing.

**Corrected 2026-09-21, from the security assessment.** Two of the claims above were not true as
shipped in 4.5.

The in-progress guard protected nothing. It compared URL values, and the URL handed to the
recorder is not equal to the one a directory scan returns for the same file, so the filter matched
nothing and the recording being written was offered up like any other. The test above could not
catch it, because it built both URLs the same way. `keeping` is now a set of standardized paths,
and it is a set because two cameras means two files open at once, which the original `URL?` could
not express at all. Unreachable in 4.5, since trimming only runs when nothing is recording.

The file recogniser accepted folders. `ownRecordings` never checked that an entry was a regular
file, so a folder whose name parsed as a recording became a 0-byte recording, and `removeItem` on
a folder takes everything inside it. Reproduced against a real folder before fixing: a file inside
such a folder was destroyed. It now asks for `isRegularFileKey`, which also excludes symlinks.

Both are fixed with tests that fail against the old code. Worth keeping in mind for whoever reads
the Behaviour section above: two of those ticked boxes were ticked by tests that agreed with the
bug.

`PopoverNotice` now weighs three things that already happened against one risk that hasn't, and
takes the most recent of the three. That replaces the pair-wise comparison 0027 added, which
wouldn't have extended to a third claimant.

Settings gained a row: GB to keep, 0 meaning keep everything, which is the default. The stop
threshold is not a setting, so nobody has to know it exists.

**Manual checks skipped, 2026-09-20,** by Jake's decision. One of them was the check this spec
was most afraid of, so it became a test instead: `testOnlyOnCuesOwnFilesAreOfferedForDeletion`
writes OnCue recordings and somebody else's files into a real folder, scans it through
`ownRecordings()`, and asserts that a limit small enough to want the folder emptied still reaches
nothing but OnCue's own. That covers the folder scan, which had no test before, only the name
parser underneath it.

**Shipped in 4.5, 2026-09-21,** build 846. Verified from the public URL: the download matches
the repo's zip by SHA-256, the staple validates, and Gatekeeper accepts it offline.

What stays unverified is the wiring between those rules and the interface. The rules are tested
and the app has not been watched doing any of it: that the stop actually says so in the popover,
that a deletion actually says so, that the Settings field saves and reads back, and that with the
limit at 0 a real armed session deletes nothing. If the window misbehaves on a real folder, those
are the four places to look first.

## Open questions
1. Resolved (Jake, 2026-09-20): both. Stopping cleanly is the default, and a rolling window is
   something you switch on.

   Deleting has to be available because it's what a security camera is: every DVR keeps a rolling
   window, because the thing you're watching for hasn't happened yet and last month's footage is
   worth less than tonight's. Making "stop when full" the only option answers the problem by
   declaring it out of scope.

   It can't be the default because OnCue doesn't own its storage the way a DVR does. It writes to
   your Mac, possibly to Movies, possibly to a folder that syncs. A DVR overwriting its own disk
   is nothing like an app deleting files from a home directory while nobody's there.

   Stopping is worth building either way, and it isn't what happens now: today OnCue records into
   a full disk, fails, and 0027 turns the icon yellow afterwards. Checking free space before a
   recording starts and stopping deliberately is better than failing, and it means OnCue destroys
   nothing unless it was asked to.
2. Resolved (Jake, 2026-09-20): free space decides when to stop, total size decides what the
   rolling window keeps. One number each, and each measures the thing it's actually about.

   The stop threshold has to be free space, since it's about protecting the Mac, and it has to be
   conservative: a recording lasts as long as the activity does, so OnCue can't know how big the
   next one will be.

   Age is ruled out rather than offered. It's the one people understand, but it doesn't solve the
   problem: "keep the last 7 days" frees nothing on a busy night, because if two cameras produce
   40 GB in eight hours then nothing is 7 days old yet and the disk fills anyway. A retention rule
   that can decline to free anything isn't one.

   Free space is also ruled out for the window itself, despite sounding protective, because it
   couples footage to unrelated disk use: download something large and last week's recordings
   vanish for reasons nothing to do with OnCue. Surprising deletions are what this spec is most
   afraid of. Total size costs legibility, since it doesn't say how far back you can look, but
   it's a promise OnCue can keep whatever kind of night it is.
3. Resolved (Jake, 2026-09-20): the stop threshold is always on and isn't a setting; the rolling
   window is the setting, off by default. One knob, not two, and the only behaviour you have to
   ask for is the one that deletes.

   Nobody sensibly wants "keep recording until the disk is completely full", so making the stop a
   choice adds something to explain and to get wrong for no gain. A fixed conservative headroom
   works on an 8 TB drive and a 250 GB one.

   This also removes the worry that made the question: off-by-default no longer means the disk
   fills for someone who never opens Settings, because the stop catches them. They get a Mac that
   doesn't fill and an OnCue that says it stopped, which is a decent outcome rather than a
   compromise.
4. Resolved (Jake, 2026-09-20): only files whose names OnCue itself would have written. Nothing
   else in the folder, ever.

   The deciding case came from Jake's own setup: during this session recordings were going to
   `~/Downloads`. A rolling window that deleted "the oldest files in the recordings folder" would
   have started deleting his downloads. Spec 0017 lets the folder be anywhere, so the folder is
   not OnCue's to manage; the only safe unit is a file OnCue can recognise as its own, by a name
   that parses as its timestamp, its devices, `.mov`, and optionally 0024's missing-seconds
   suffix.

   That gives a property worth keeping on purpose: renaming a recording protects it. Someone who
   finds footage that matters and calls it "front door, Tuesday" has taken it out of the set OnCue
   will ever delete, with no UI needed. Nobody should later make the matching cleverer and break
   that.

   Noted rather than solved: 0017 allows a synced folder, where a deletion reaches every device
   the user owns. OnCue can't reliably detect one and shouldn't guess. The window being opt-in is
   the protection, and the help text should say plainly what it does.
