---
title: Recording file names include the devices used
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-19
commits: 90351c0 (spec), 932b5ce (implementation)
---

## Problem
Recordings are named only by their start time ("2026-09-19 12.14.06.mov"). Now that OnCue can
switch cameras and mics, fall back to another device, or record audio or video only (specs 0003 to
0005), a file's name doesn't say what it came from; you have to open it to find out.

## Non-goals
- Renaming recordings already on disk.
- Changing the folder (`~/Movies/OnCue`) or the timestamp format.
- Recording metadata inside the file.

## Behaviour (acceptance criteria)
- [x] A new recording's name is its start time followed by the camera and mic it used, e.g.
      "2026-09-19 12.14.06 - MacBook Pro Camera + MacBook Pro Microphone.mov". Unit test.
- [x] An audio-only recording names only the mic, a video-only recording only the camera. Unit test.
- [x] Characters macOS can't use or shows oddly in a file name ("/" and ":") are replaced, and a very
      long name is shortened so the whole name stays within the file system's 255-byte limit.
      Unit test.
- [x] Files that land in the same second still get numbered, as in spec 0003. Unit test.
- [x] The timestamp stays first, so recordings still sort by time in Finder. Unit test.
- [x] `scripts/check` passes.

## Design
- `FileOutputManager` builds the name from the start time and the camera and mic names, through a
  pure function next to `uniqueMovieURL`, so it's unit-tested without devices.
- `CaptureManager` passes the current camera and mic names when it starts a recording, through
  `RecordingManager.startRecording(to:)`, which already chooses the file.
- The separators are file-name formatting, not prose; the device names come from macOS.
- **Built (2026-09-19):** `FileOutputManager.movieName(timestamp:cameraName:microphoneName:)`; "/"
  and ":" become "-"; the name is cut to leave room for a " 999" number and ".mov" within 255 bytes.
  `startRecording(to:cameraName:microphoneName:)` takes the names from `CaptureManager`'s current
  devices when a recording starts, including a restart after an interruption.

## Gates
- [x] `scripts/check` passes

## Tasks
- [x] Name function with tests (format, one device, unsafe characters, length, numbering)
- [x] Device names passed through to the file name
- [x] Manual check: a recording's name matches its devices, Verification filled in

## Verification
- `FileOutputManagerTests` adds 5: both devices after the time, only the device used (and just the
  time with neither), unsafe characters replaced, long names within the limit with room for a
  number, numbering still applied. 59 tests pass on a clean build with no warnings (`scripts/check`).
- Jake's manual check (2026-09-19): new recordings' names match the devices they used.

## Open questions
Resolved by Jake, 2026-09-19: both devices, " - " after the time and " + " between them.
