---
title: Keep recording through a camera switch
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-19
commits: b83ad53 (spec), 164c937 (implementation)
---

## Problem
Switching cameras while a recording is in progress stops the capture session, which ends the file.
`RecordingManager` still says `.recording`, so every trigger after the switch only pushes the
stop timer back instead of starting a file. Nothing is recorded again until a full timeout passes
with no motion or sound. If activity continues, which is exactly when a recording matters, it
never records. A camera unplugged mid-recording, or a capture session runtime error, ends the file
the same way and leaves the same stuck state. The file that ended is never checked for errors.

## Non-goals
- Stitching the before and after files into one.
- Changing what a switch does while armed but not recording; that already works.
- Picking up a camera or mic that connects while OnCue is running; that is spec 0004.

## Behaviour (acceptance criteria)
- [x] An interruption (camera switch, camera unplugged, session runtime error) during a recording
      ends the file and sets the state to `.armed`; when capture is running again, a new file
      starts with the stop timer restarted. Unit tests with a fake recorder; manual check with a
      webcam: switch while recording, and unplug while recording, each leaving two playable files.
- [x] The state never claims `.recording` while the recorder isn't recording: a file that ends
      on its own (error, disk full) moves the state to `.armed`, so the next trigger starts a new
      file. Unit test with a fake recorder.
- [x] A disarm during an interruption wins: no new file starts afterwards. Unit test.
- [x] An interruption while armed but not recording leaves it armed, with no file. Unit test.
- [x] A trigger can fire only if it's on and its device is present: motion needs a camera, sound
      needs a mic. Arm is disabled while unarmed with no trigger that can fire, as in spec 0002,
      now counting devices. Unit test on the rule.
- [x] Removing the only device that can still trigger, or both devices, while arming, armed, or
      recording disarms automatically, ending any recording. Unit test on the rule; manual check:
      motion only, unplug the only camera while armed.
- [x] With the camera gone but the sound trigger on and a mic present, OnCue stays armed, capture
      continues audio-only, and sound still starts a recording (an audio-only file). The motion
      column is disabled while there's no camera. Manual check: sound trigger on, unplug the
      camera while armed, clap.
- [x] Unplugging the mic mid-recording while motion can still fire continues video-only in a new
      file. Manual check.
- [x] A recording that ends with an error is logged with the file and the error. Manual check (log).
- [x] `scripts/check` passes.

## Design
- **Seam for tests:** a `MovieRecorder` protocol (`startRecording(to:recordingDelegate:)`,
  `stopRecording()`, `isRecording`) that `AVCaptureMovieFileOutput` conforms to in an extension.
  `RecordingManager` takes a `MovieRecorder`, so tests pass a fake.
- **RecordingManager:** `suspendRecording() -> Bool` ends a recording in progress (state to
  `.armed`) and returns whether one was; `resumeRecording(to:)` starts a new file only if still
  `.armed`, so a disarm in between wins. `recordingDidFinish(error:)`, called from
  `FileOutputManager`, moves `.recording` to `.armed` when the recorder stopped on its own.
- **CaptureManager** coordinates the three interruptions the same way: suspend on the main queue,
  reconfigure or restart the session on the session queue, then resume on the main queue if a
  recording was suspended and the session is running.
  - Camera switch: `changeVideoCaptureDevice`.
  - Device unplugged: `AVCaptureDevice.wasDisconnectedNotification` for the current camera or mic;
    reconfigure with the first remaining camera and mic, either of which may now be missing.
  - Runtime error: `AVCaptureSession.runtimeErrorNotification`; restart the session.
- **Device availability (Jake, 2026-09-19):** `RecordingManager.canAnyTriggerFire` gains
  `cameraAvailable`; a trigger counts only if it's on and its device is present. `configureSession`
  takes an optional camera, so capture can run audio-only, and the motion scan idles without
  frames. `CaptureManager` reports camera and mic availability together through one delegate
  method, replacing `audioAvailabilityChanged`, and the popover disables whichever column has no
  device.
- **One owner for auto-disarm:** the check moves out of the popover into `RecordingManager`,
  which re-evaluates when device availability changes and when a toggle changes, so disarming
  doesn't depend on the popover having loaded.
- **Why a new file:** a movie file can't stay open across a session restart, and the new file
  keeps the gap to the restart itself, about a second.
- State reads and changes stay on the main queue, as they are today.
- **Decisions while building (2026-09-19):**
  - Resuming reuses `startRecording(to:)`; its `.armed` guard already makes a disarm win, so no
    separate `resumeRecording`.
  - File names are to the second and a restart takes about that long, so a new name can collide
    with the file just ended, and the recorder won't overwrite. `FileOutputManager` numbers
    later files ("… 2.mov") and never reuses a name it handed out this session.
  - A finished file is matched to the current one by path, not by `URL` equality or the
    recorder's `isRecording`: the URL handed out is relative and the one reported back may be
    absolute, and `isRecording` can read false while a new file is starting.
  - `RecordingManager` takes its `UserDefaults`, so the tests flip toggles in a throwaway suite
    instead of the app's real settings. Device presence is unknown, so treated as absent, until
    capture first reports it; nothing can arm before then.
  - Arming with a zero countdown used to count down forever; it now arms immediately.

## Gates
- [x] `scripts/check` passes
- [x] Manual checks with a USB webcam: switch while recording, unplug while recording

## Tasks
- [x] `MovieRecorder` protocol and fake; `RecordingManager` suspend, resume, and finish handling,
      with unit tests (before any camera work)
- [x] Camera switch: suspend and resume around reconfiguration
- [x] Device availability in the trigger rule and auto-disarm, moved into `RecordingManager`, with tests
- [x] Optional camera in `configureSession`; audio-only capture; popover disables the motion column
- [x] Device unplugged: reconfigure with what's left, then resume or disarm
- [x] Runtime error: restart the session, then resume
- [x] Log recording errors
- [x] Manual checks with the webcam, Verification filled in

## Verification
- Unit tests, 34 in total, pass on a clean build with no warnings (`scripts/check`). New:
  - `RecordingInterruptionTests` (fake recorder): suspend ends the file and returns to armed;
    suspend while armed does nothing; resume starts a new file; a disarm in between wins; a file
    ending on its own returns to armed; an earlier file finishing late leaves the new recording
    alone; a file stopped on purpose changes nothing when it finishes.
  - `DeviceLossTests` (throwaway defaults): nothing arms before devices are known; losing the only
    camera for motion disarms; losing the camera stays armed while sound can trigger; losing both
    mid-recording disarms and ends the file; turning off the last trigger disarms.
  - `FileOutputManagerTests`: numbered names in the same second; no name handed out twice.
  - `RecordingManagerTests`: motion needs a camera to count.
- Jake's manual checks with the webcam (2026-09-19): all pass, including unplugging the camera and
  the mic mid-recording and the device-loss disarm cases.

## Open questions
Resolved by Jake, 2026-09-19:
- Continue in a new file after a switch, rather than blocking switches or disarming.
- Fold camera loss and runtime errors into this spec.
- Unit tests land first; manual checks wait for the webcam.
- Only camera or both devices removed while armed: disarm automatically, unless another enabled
  trigger still has its device (Jake).
- Devices reconnecting mid-session: a follow-up spec, 0004 (Jake).
