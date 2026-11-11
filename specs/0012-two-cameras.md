---
title: Watch two cameras at once
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-19
commits: 895094f (spec), 9d77713 (implementation)
---

## Problem
OnCue watches one camera. A Mac with a built-in camera and a USB webcam can cover two views (a
door and a desk, a room from two sides), but today the second camera sits unused unless it's
swapped in. Two is the realistic count for local cameras on one Mac; more means network cameras,
which is a different product.

## Non-goals
- More than two cameras, or network (IP/RTSP) cameras.
- Combining two cameras into one video file.
- A second microphone; there's still one mic, chosen as in spec 0005.

## Behaviour (acceptance criteria)
- [x] **Trial first:** on this Mac, two capture sessions run at the same time, the built-in camera
      and the USB webcam, each delivering frames, and each can record a file while the other does.
      Findings recorded in Verification before any other task starts.
- [x] Settings chooses a second camera, or none; it's remembered like the first (spec 0004).
      With none chosen, OnCue behaves exactly as today. Manual check.
- [x] Each camera has its own motion detection. Motion on either camera, or sound, starts or
      extends recording on both cameras. Unit test on the trigger routing; manual check.
- [x] Each camera records its own file, named with its devices (spec 0009). Manual check.
- [x] The popover's Motion column shows a meter and a trigger slider for each camera, each named for
      its camera. Manual check.
- [x] The preview window shows both cameras side by side. Manual check.
- [x] Losing one camera keeps OnCue armed on the other; losing both follows the device-loss rule
      from spec 0003 (disarm unless sound can still trigger). Unit test; manual check.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- **Per-camera pipeline:** today's single-camera parts of `CaptureManager` (session, video and
  movie outputs, motion renderer, frame buffers, file recorder) move into a `CameraPipeline`;
  `CaptureManager` owns one or two. Interruption handling (spec 0003) runs per pipeline.
- **Recording state:** `RecordingManager` tracks one recording per pipeline. Arm state stays
  single: armed means both cameras are watching.
- **Audio:** one mic, added to both sessions; the trial showed macOS allows it and both files get
  audio.
- **Trigger routing:** any trigger (motion on either camera, or sound) starts or extends recording
  on every running pipeline. A pure function decides this, so it's unit-tested without cameras.
- **Thresholds:** each camera has its own motion threshold, saved per camera ID; the second camera's
  starts at the first's value.
- This is a large change: the single-camera assumption runs through specs 0003 to 0005. The trial
  keeps the cost of finding out small.

- **Built (2026-09-19):**
  - `CaptureManager` owns two pipelines; the second runs only with a second camera. The mic goes into
    both. The second camera is saved as `secondCameraID`; `DevicePreference.second` picks it only if
    it's connected and isn't the first camera (no fallback), so a lost first camera can move the
    second one into the first slot, leaving no second camera.
  - Any trigger records on every running pipeline (`DevicePreference.recordingPipelines`), through
    `RecordingManager.startRecording(to: [RecordingTarget])`: one file per camera, each named for
    its camera. One file ending on its own leaves the other recording; the state drops to armed only
    when none are left.
  - Motion counts as available while either camera is there, so losing one camera keeps OnCue armed
    on the other; losing both goes through the spec 0003 rule.
  - Motion thresholds are per camera (`MotionDetector.threshold(cameraID:)`); one never set falls
    back to the last threshold set, so a new second camera starts where the first is.
  - Settings: a second-camera picker under the camera picker, leading with a "none" entry (copy,
    drafted with a marker) and listing the connected cameras other than the first.
  - Popover: the second camera's name, meter, and slider are built in code under the first's in the
    Motion column, shown only with a second camera; the popover grows to fit and the arm state moves
    below them. The Motion trigger checkbox covers both cameras.
  - Preview: the storyboard's preview view and a second one made in code sit in a row that shows the
    second only with a second camera; the window's aspect doubles in width. The title becomes
    "OnCue - [first] + [second]", joined as file names are.

## Gates
- [x] `scripts/check` passes
- [x] Manual checks with the built-in camera and the USB webcam

## Tasks
- [x] Trial: two sessions, two cameras, frames and recording from both; findings in Verification
- [x] Revisit this spec with the trial's findings before building
- [x] `CameraPipeline` extracted, one camera, no behaviour change, existing tests green
- [x] Second camera setting in Settings
- [x] Second pipeline, trigger routing with tests, per-camera recordings
- [x] Popover and preview for two cameras
- [x] Device loss per camera, with tests
- [x] Manual checks, Verification filled in

## Verification
- **Trial (2026-09-19)**, on this MacBook Pro with the built-in camera and a Logitech C920 over USB.
  A script run from the shell got no frames because it had no camera permission, so the trial ran
  inside a signed OnCue build behind a temporary debug launch flag, since removed and never
  committed.
  - Two capture sessions ran at once, one per camera, each with its own video data output and
    movie file output. Both delivered frames: about 24 fps from the C920 and 29 fps from the
    built-in camera.
  - The one mic was added to both sessions, and both files have an AAC audio track alongside
    1080p H.264 video. So both cameras' recordings can carry sound; no need to attach the mic to
    one session only.
  - Recording both at once: 7.1 s and 7.0 s files from an 8 s window, against 7.3 s for one
    camera alone. The missing time is the movie output's start-up, present with one camera too.
    The very first run after plugging in the C920 gave much shorter files (0.5 s and 1.1 s from a
    5 s window), which looks like the camera's cold start.
  - The design holds as written; the only change is that the mic goes into both sessions.
  Jake reviewed the findings and said go (2026-09-19).
- **Pipeline extraction:** `CameraPipeline` owns one camera's session, video and movie outputs,
  motion renderer, frame handling, mic metering, and runtime-error observation, reporting motion,
  preview frames, and errors through `CameraPipelineDelegate`. `CaptureManager` keeps device choice,
  permission, interruptions, the audio meter timer, and recording control, with one pipeline.
  Clean build, 62 tests pass. Nothing automated exercises capture itself, so a run of the app to
  confirm nothing changed is the check before the second pipeline goes in. Jake ran it: the app
  works the same (2026-09-19).
- New tests: `TwoCameraRecordingTests` (4: a file per camera named for it, stopping ends both, one
  file ending leaves the other recording, an interruption suspends both); `DevicePreferenceTests`
  (4: second camera chosen when connected, none without a choice or when gone, never the first,
  recording on every running camera); `MotionDetectorTests` (2: per-camera thresholds, a new camera
  starting at the last set); `PreviewTitleTests` (1: both names). 73 tests pass on a clean build with
  no warnings; `scripts/check` passed in full once Jake had the copy marker struck ("No second
  camera", as drafted).
- Jake's manual checks with the built-in camera and the C920 (2026-09-19): all pass.

## Open questions
Resolved by Jake, 2026-09-19:
- Any trigger records on both cameras.
- Each camera has its own motion meter and trigger slider.
- The preview shows both cameras side by side in one window.
