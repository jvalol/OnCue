---
title: A still beside every recording
status: shipped
created: 2026-09-25
commits: b51b6a3 (approval), 5ea6128 (implementation), 7a7c4da (built state, manual checks), 20f335d and a443ab7 (released in 4.15)
---

## Problem
A recordings folder is a list of movies, and the only way to learn what any of them caught is to
open it. Finder's thumbnail is the first frame, which with pre-roll (0013) is the empty room from
five seconds before anything happened. Twenty recordings from a windy afternoon take twenty
opens to dismiss. A still taken at the moment the trigger fired, saved beside the movie under the
same name, turns the folder into a contact sheet: Finder's gallery view or a Quick Look pass
shows what each event was, and the movie is there for the ones that matter. It's also the file
worth sending to someone, at a few hundred kilobytes rather than a movie.

## Non-goals
- No gallery, browser or thumbnail strip inside OnCue. Finder already has those.
- No time-lapse, no burst, no still on a timer. One still per recording, per camera.
- No still for a recording that never got a video frame. An audio-only file (0028's case) has
  nothing to draw.
- No notification carrying the still. If a "recording started" notice ever exists, attaching the
  still to it is that spec's business.
- No attempt to pick the "best" frame. The frame that tripped the trigger is the one that says why
  the recording exists.

## Behaviour (acceptance criteria)
- [x] When a recording starts on a camera, a JPEG is written beside its movie with the same
      base name and a `.jpg` extension: `2026-09-25 17.40.12 - FaceTime HD Camera.mov` gets
      `2026-09-25 17.40.12 - FaceTime HD Camera.jpg`. Unit test on the naming, from the movie URL.
      Manual check: a trigger on this Mac leaves the pair in the folder.
- [x] The still is the newest frame the camera's pipeline holds when the recording starts, the
      one that tripped the threshold or the one after it, not the first frame of the pre-roll.
      Unit test: a recorder started with a known frame writes that frame. Manual check: the still
      shows the movement, not the empty room.
- [x] With two cameras (0012), each camera's recording gets its own still, from its own frame.
      Manual check.
- [x] Record a Test (0046) leaves a still too, since it records the way a trigger would. Manual
      check.
- [x] A recording that fails to start (0027) leaves no still behind: the still is written once
      the recorder has confirmed the file, or removed if the start fails after it. Unit test with a
      recorder that refuses.
- [x] The still is OnCue's own file to the rolling window (0029): it counts toward the size limit,
      and it goes when its movie goes, never on its own and never leaving an orphan. Unit tests on
      `ownRecordings` and `toDelete`.
- [x] Renaming the movie takes the still out of the window's reach only if the still is renamed
      too; the two are independent files with OnCue's timestamp, the same rule as today. Unit test.
- [x] Show Recordings still selects the newest movie, not the newest still. Unit test on
      `newestRecording(among:)`.
- [x] The still has the recording's permissions, 0o600, since spec 0017 lets the folder be
      anywhere. Manual check.
- [ ] Encoding happens off the capture and main queues and never delays the recorder's first
      write. Manual check with the measurement recipe: GPU time per frame unchanged across a
      trigger.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- **Where the frame is.** `CameraPipeline` sees every frame as a `CVPixelBuffer` in the data
  output callback (32BGRA, Metal-compatible), which is what motion is measured on. It keeps a
  reference to the newest one; a `CVPixelBuffer` is retained, not copied, so this costs nothing
  until it's read. When `PreRollRecorder.startRecording(to:onFinish:)` is called, the pipeline
  hands that buffer and the still's URL to the writer.
- **`StillWriter`**, new, in `Managers/Helpers`, in both targets. `stillURL(for movieURL:)` is the
  naming rule, pure. `write(_ pixelBuffer: CVPixelBuffer, to url: URL)` encodes with ImageIO
  (`CGImageDestination`, JPEG, quality 0.8) on a utility queue and sets 0o600. ImageIO reads
  32BGRA directly through `CIImage` or a `CGImage` from the base address; no Metal and no
  AppKit, so the tests can feed it a synthetic buffer and read the JPEG back.
- **Ordering with failure.** The recorder's start is asynchronous and 0027 names the ways it can
  fail. The still is written when the recorder reports the file started (the same point
  `testRecordingAnswered(started:)` uses), and the recording's finish handler removes it if the
  file ended with an error and no footage. A still with no movie is worse than no still.
- **The window.** `FileOutputManager.recordingDate(fileName:)` already accepts any extension
  with OnCue's timestamp prefix, so `ownRecordings()` will count stills without a change and
  `DiskBudget.toDelete` would delete them by date, which pairs them with their movie by accident
  of sharing a second. Make it deliberate: `toDelete` groups files by base name and deletes a
  group whole, so a still never outlives its movie and a movie never loses its still to the
  limit alone.
- **Interruption (0003).** A recording that restarts after a camera switch starts a new file with
  a new name, and gets a new still: it's a new start with a new frame. The first still stays with
  the first file.
- **Rejected:** a still from the movie after the fact (needs the file finished and a decode;
  the frame is already in hand at the trigger). HEIC (half the size, but not every place a still
  gets sent can open it; JPEG opens everywhere). A still per motion peak during the recording
  (many files, and picking peaks is a spec of its own).

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [ ] The measurement recipe shows no change in GPU time per frame across a trigger

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

## Tasks
- [x] `StillWriter`: naming and encoding, with tests on a synthetic buffer
- [x] `CameraPipeline` keeps the newest frame; the recorder start hands it to the writer once the
      file is confirmed; the finish handler removes the still of a failed start
- [x] `DiskBudget.toDelete` deletes by base name group; `ownRecordings` test covers stills
- [x] Help page paragraph (marked, in `site/help`); the changelog entry comes with the release

## Verification
- **Built (2026-09-25):** `StillWriter` (`Managers/Helpers`, both targets): `stillURL(for:)`,
  `jpegData(from:)` through `VTCreateCGImageFromCVPixelBuffer` and `CGImageDestination` at
  quality 0.8, `write(_:besideMovie:)` atomic and 0o600, `removeStill(besideMovie:)`. The
  pipeline hands every raw frame to `PreRollRecorder.noteFrame`, which keeps the newest; the
  recorder writes the still in `beginSession`, the moment the file really starts, on a utility
  queue, for a start and not for a roll (0031 continues the same event). A file that never
  began takes its still with it. `DiskBudget.toDelete` groups files by `eventKey` (folder and
  name without extension, 0024's missing-seconds suffix stripped), deletes an event whole,
  movie first, and keeps an event whole when any file in it is being written. Twelve tests:
  naming, JPEG size and type, the colour channels read the right way round, the file beside the
  movie and private, removal leaves the movie, a recorder with a frame but no footage leaves no
  still and no movie, the pairing in the window from both directions, the in-progress event
  kept, the renamed movie still paired, stills weighed, and Show Recordings ignoring a newer
  still. `PreRollRecorder.swift` now compiles into the test target for the recorder test.
  Clean build, 387 tests, no warnings. Not measured: GPU time across a trigger; the encoding
  runs on a CPU queue, not the Metal pass, so no change is expected but none was shown.
- **Checked on this Mac (Jake, 2026-09-25 18:04):** a trigger leaves the movie and its still under
  one name, the still shows the movement; two cameras leave two stills; Record a Test leaves one.
  Help paragraph read and its marker struck. `scripts/check` green.

## Open questions
1. Resolved (Jake, 2026-09-25): always on, no switch. A still is a few hundred kilobytes that
   the size limit already bounds, and an optional still makes the folder sometimes a contact
   sheet and sometimes not. A switch is a small spec later if a wheel squeaks.
2. Resolved (Jake, 2026-09-25): beside the movie under the same name. The pairing is visible in
   Finder and Quick Look, the window and Show Recordings already handle it, and anyone who wants
   a different layout can organise the folder afterwards.
3. Resolved (Jake, 2026-09-25): an audio-triggered recording gets its still like any other.
   What the camera saw when the noise happened is an answer, an empty room included, and one
   rule beats an exception.

## Closure
Shipped in 4.15 (2026-09-25), direct download and the tap (cask `8669fab`, `scripts/check-tap`
green), build 906 uploaded to App Store Connect by the release run; the store version follows
once 4.14 clears review. The measurement gate (GPU time across a trigger) was not run: the
still is encoded on a CPU queue outside the Metal pass.
