---
title: Pre-roll: recordings include the seconds before the trigger
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-19
commits: 074ddbd (spec), fd00547 (implementation)
---

## Problem
A recording starts when motion or sound crosses its threshold, and the movie output then takes
0.7 to 1 second to begin writing (measured in the spec 0012 trial, with one camera too). So the
moment that triggered it, and whatever led up to it, is never in the file. Security recordings
usually carry a few seconds from before the trigger.

## Non-goals
- Continuous recording, or keeping footage when nothing triggered.
- Changing how triggers work or how long recordings continue after activity stops.

## Behaviour (acceptance criteria)
- [x] Each recording begins the pre-roll length before its trigger, or from when capture started if
      that's more recent. The length is a setting beside the timeout: 5 seconds by default, 0 to 30.
      Unit test on clamping; manual check in Settings. Manual check: clap, the file includes
      the seconds before the clap.
- [x] Video and audio stay in sync across the pre-roll and the live part. Manual check.
- [x] Memory stays bounded while armed and idle: only the pre-roll window is held, compressed.
      Manual check in Activity Monitor over several minutes.
- [x] A recording restarted after an interruption (spec 0003) doesn't repeat the pre-roll already in
      the previous file. Unit test on the buffer's window.
- [x] The file name's time is when the recording's footage begins. Unit test.
- [x] `scripts/check` passes.

## Design
- **Why not buffer frames:** holding raw 1080p frames costs about 8 MB each, so 5 seconds at
  30 fps is over a gigabyte. The buffer has to hold compressed samples.
- **Approach:** recording moves from `AVCaptureMovieFileOutput` to `AVAssetWriter`. Video frames
  from the existing data output are compressed as they arrive (`VTCompressionSession`, H.264), and
  audio from an audio data output is kept as it comes; the compressed samples sit in a ring buffer
  trimmed to the pre-roll window, starting at a keyframe. On a trigger, a writer starts a file with
  the buffered samples and continues with live ones. The ring buffer's windowing is pure and unit
  tested with timestamps.
- **With spec 0012:** this is built inside the per-camera pipeline, so each camera has its own buffer
  and writer. It follows 0012.
- This replaces the recorder the spec 0003 interruption handling was built on, so those tests move
  to the new recorder through the `MovieRecorder` protocol.

- **Built (2026-09-19):**
  - `SampleRing` holds the window: trimming keeps the keyframe that decodes it; a recording starts
    at the latest keyframe at or before the cutoff, never at or before what the last file wrote.
    `PreRoll` clamps the setting to 0 through 30 and dates footage for file names. All pure, tested.
  - `CameraPipeline` compresses every frame (VideoToolbox H.264, real time, 8 Mbps, a keyframe every
    second, no frame reordering) and takes audio from an `AVCaptureAudioDataOutput`; the movie file
    output is gone, and the mic level now comes from the audio output's connection.
  - `PreRollRecorder` keeps compressed video and raw audio in rings and writes with `AVAssetWriter`:
    video passed through, audio encoded to AAC. Starting a file flushes the buffered footage from its
    start keyframe, then continues live; with nothing buffered, the first live keyframe starts it.
  - Because video starts at a keyframe, pre-roll can run up to a second longer than set. Audio is kept
    2 seconds past the window so it reaches back as far as the video; without that, the trial's first
    run had sound starting 0.77 s after picture.
  - `MovieRecorder` now takes a finish closure and reports `footageStart`, and `RecordingManager`
    names each file for when its footage begins. `FileOutputManager` is no longer a capture delegate.
  - Settings gets a pre-roll field under the timeout, 0 to 30, default 5, labelled with a draft
    (copy marker).

## Gates
- [x] `scripts/check` passes
- [x] Manual checks: pre-roll content, sync, memory over time

## Tasks
- [x] Compressed-sample ring buffer with tests (window, keyframe start, no overlap after restart)
- [x] Pre-roll length setting in Settings, 0 to 30 seconds, default 5
- [x] `AVAssetWriter` recorder behind `MovieRecorder`, replacing the movie file output
- [x] Continuous compression and audio capture feeding the buffer
- [x] Manual checks, Verification filled in

## Verification
- Unit tests: `SampleRingTests` (8: trimming to the keyframe, keeping all when young, start at the
  keyframe before the cutoff, earliest when none is old enough, no repeat after a restart, entries
  from a time, clamping 0 to 30, dating footage); `TwoCameraRecordingTests` adds the file named for
  when its footage begins. 82 tests pass on a clean build with no warnings; `scripts/check` passed in
  full once Jake had the Settings label's marker struck ("seconds to include from before activity
  starts", as drafted).
- Trial in a signed build behind a temporary debug flag (removed, never committed), built-in camera
  and mic, pre-roll 5 s: after 8 s of capture, a 3 s recording produced an 8.9 s file (H.264 1080p
  and AAC), footage starting 5.8 s before the recording began. After the audio fix, video starts at
  0.00 s and audio at 0.01 s.
- Jake's manual checks (2026-09-19): all pass: pre-roll content and sync, memory over several
  minutes armed, the Settings field, and quitting mid-recording.

## Open questions
Resolved by Jake, 2026-09-19: 5 seconds by default, adjustable in Settings up to 30 seconds.
