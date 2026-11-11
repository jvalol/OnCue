---
title: Show recordings from the popover menu
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-19
commits: cec44f3 (spec), d6a937b (implementation)
---

## Problem
Recordings go to `~/Movies/OnCue`, but nothing in OnCue says so or leads there. Finding them
means knowing the path and browsing to it in Finder.

## Non-goals
- Browsing or playing recordings inside OnCue.
- Changing where recordings are saved.

## Behaviour (acceptance criteria)
- [x] The popover's menu has an item that opens the recordings folder in Finder with the newest
      recording selected, or just the folder when there are none. Unit test on picking the newest;
      manual check.
- [x] If the folder is missing (deleted since launch), it's created first, so the item always opens
      it. Unit test on the folder being ensured; manual check.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- `PopoverMenu` gains the item, above Preferences. After making sure the folder exists, it calls
  `NSWorkspace.shared.activateFileViewerSelecting` with the newest recording, or
  `NSWorkspace.shared.open` on the folder when there's none.
- The newest is the `.mov` with the latest creation date, chosen by a pure function over the
  folder's files and their dates so it's unit-tested. File names can't decide it, since a
  device-named recording and a numbered one from the same second don't sort by time. The sandbox's Movies
  read-write entitlement already covers the folder.
- The folder-creation code in `FileOutputManager.init` moves into a method the menu item can call
  again, which the unit test exercises on a temporary folder.
- The item's title is copy: the draft carries `[COPY - Jake]`.
- **Built (2026-09-19):** `FileOutputManager` takes its folder (default `~/Movies/OnCue`) so tests
  use a temporary one; `ensureFolderExists()` and `newestRecording()` are public for the menu item;
  `newestRecording(among:)` is the pure choice. The item is drafted as "Show Recordings".

## Gates
- [x] `scripts/check` passes

## Tasks
- [x] Folder-ensuring method with a test
- [x] Newest-recording choice with a test
- [x] Menu item opening the folder with the newest selected
- [x] Manual check, Verification filled in

## Verification
- `FileOutputManagerTests` adds 3: the newest by creation date over name order and ignoring
  non-movie files, none when empty, a deleted folder recreated. 62 tests pass on a clean build
  with no warnings; `scripts/check` passed in full once Jake had the copy marker struck.
- Jake's manual check (2026-09-19): the menu item opens Finder with the latest recording selected.

## Open questions
Resolved by Jake, 2026-09-19: select the newest recording; open the folder alone when there's none.
