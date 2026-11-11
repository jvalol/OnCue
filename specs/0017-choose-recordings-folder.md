---
title: Choose where recordings are saved
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-19
commits: 9f0de23 (spec), d177964 (implementation)
---

## Problem
Recordings always go to `~/Movies/OnCue`. There's no way to put them on an external disk, a
cloud-synced folder, or anywhere else. OnCue's sandbox only grants the Movies folder, so the app
couldn't write elsewhere even if it wanted to.

## Non-goals
- Uploading anywhere, or integrating with a cloud service; a synced folder is just a folder.
- Moving recordings already written: changing the folder leaves them where they are.
- A size limit or clean-up of old recordings (worth its own spec).

## Behaviour (acceptance criteria)
- [x] Settings has a recordings folder, showing where recordings go, with a button to choose another
      through the standard macOS folder picker. Manual check.
- [x] Recordings go to the chosen folder, and it's still chosen after quitting and reopening OnCue.
      Manual check, including a folder outside Movies and one on an external disk.
- [x] Show Recordings opens the chosen folder.
- [x] If the chosen folder can't be used at launch (deleted, or on a disk that isn't attached),
      OnCue falls back to `~/Movies/OnCue`, says so in Settings, and keeps the choice for when the
      folder returns. Unit test on the fallback rule; manual check by unplugging a disk.
- [x] Settings has a reset that puts recordings back in `~/Movies/OnCue` and forgets the choice.
      Unit test on the rule; manual check.
- [x] With no folder chosen, everything works as it does today. Unit test.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- The sandbox needs `com.apple.security.files.user-selected.read-write`, and the choice is kept as
  a security-scoped bookmark in UserDefaults, resolved at launch and wrapped in
  `startAccessingSecurityScopedResource()`. The existing Movies entitlement stays for the default.
- `FileOutputManager` already takes its folder, so the change is choosing which folder it gets:
  a `RecordingsFolder` that resolves the bookmark, falls back, and reports which is in use. The
  resolution and fallback rules are pure and unit-tested; the bookmark itself is exercised by hand.
- Settings shows the folder's name and path, with a Choose button; the fallback note and the button's
  label are copy.

- **Built (2026-09-19):**
  - `com.apple.security.files.user-selected.read-write` added to the entitlements; the Movies
    entitlement stays for the default folder.
  - `RecordingsFolder` resolves the bookmark (refreshing it when stale), starts security-scoped
    access, and decides between the chosen folder and the default; `inUse` is the pure rule.
  - `FileOutputManager` takes the folder from `RecordingsFolder` and can be pointed at a new one;
    `RecordingManager.recordingsFolderChanged()` does that when Settings changes it, and Show
    Recordings follows automatically.
  - Settings shows the folder with a tilde path, a Choose button (an `NSOpenPanel` for directories)
    and a Reset button, plus an orange note when the chosen folder is missing.

## Gates
- [x] `scripts/check` passes
- [x] Manual checks: a folder outside Movies, a folder on an external disk, and that disk unplugged

## Tasks
- [x] `RecordingsFolder` with tests: chosen, default, fallback when unavailable
- [x] Entitlement, bookmark saved and resolved, folder used for recordings and Show Recordings
- [x] Settings row with the folder and a Choose button, and the fallback note
- [x] Update the site's wording, which says recordings go to the Movies folder (spec 0016)
- [x] Manual checks, Verification filled in

## Verification
- `RecordingsFolderTests` (4): the default when nothing was chosen, the chosen folder when it's
  reachable, falling back when it's missing while keeping the choice, and choosing then resetting
  through a throwaway defaults suite. 94 tests pass on a clean build with no warnings
  (`scripts/check`).
- Jake's manual checks (2026-09-19): all pass: choosing a folder outside Movies and recording into
  it, the choice surviving a restart, the fallback when the folder isn't available, and Reset.
- Recording into a chosen folder is also what turned up the unfinalized-file bug fixed alongside
  spec 0019: files written anywhere were missing their index when OnCue was killed mid-recording.

## Open questions
Resolved by Jake, 2026-09-19: recordings already written stay where they are; Settings gets a reset
button back to the default folder.
