---
title: Release the cameras when nothing needs them
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-19
commits: ec186e3, e11d19c, 8bfe926, fbf1643 (spec), ee79bbb (implementation)
---

## Problem
OnCue opens its capture sessions when the app launches and holds them until it quits. It is
watching the room the entire time it is running, whether or not it is armed, whether or not anyone
is looking at the meters.

Nothing needs that. Unarmed with the popover closed, the frames feed meters nobody can see and a
pre-roll buffer that no recording will use. Meanwhile holding the camera has costs that used to be
invisible and are not any more: on macOS 26.2 it turns on Edge Light, so OnCue lights the room it
is supposedly watching discreetly (spec 0022), the camera indicator is lit whenever OnCue is open,
and two capture sessions plus continuous H.264 compression run for nothing.

The deeper problem is that the glow, the indicator, and the running camera all stop meaning
anything. They should mean OnCue is watching. Today they mean OnCue is open.

## Non-goals
- The Edge Light warning itself. Spec 0022 covers saying it's happening; this one is about it not
  happening when OnCue isn't watching.
- Changing what arming does, or the countdown.
- Separating the microphone from the cameras. It follows the same rule (question 1), so the
  sessions start and stop whole rather than being reconfigured to mic-only.

## Behaviour (acceptance criteria)
- [x] Unarmed with the popover and preview closed, no camera is open: the camera indicator is off
      and Edge Light is not active. Manual check.
- [x] Opening the popover opens the cameras, and the meters move within a second or two. Manual
      check.
- [x] Arming opens the cameras and keeps them open until disarmed, popover open or not. Manual
      check.
- [x] Nothing is missed at the start of a recording because the camera had just opened: pressing
      Arm starts capture immediately, and the countdown outlasts the warm-up. Unit test that
      `.arming` is itself a reason to capture, plus a manual check that a trigger immediately
      after arming records.
- [x] Pre-roll reaches back as far as the cameras have been running since the last recording
      ended, capped at the setting. It is shorter when a trigger comes soon after capture started,
      which is accepted. Manual check on a recording's first seconds.
- [x] Whatever holds the cameras open is one rule with the reasons named, tested, and it never
      leaves them open with no reason or closed with one. Unit test.
- [x] Disarming during a recording finishes the file before capture stops, and the file opens.
      Unit test on the rule, plus a manual check that the resulting `.mov` plays.
- [x] The microphone follows the cameras, so no indicator is lit when nothing needs it. Manual
      check.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- The rule is a set of reasons to be capturing: the arm state is anything but unarmed, the popover
  is open, the preview window is open. A pure function turns that set into "capture or not", so
  it's testable, and `CaptureManager` starts and stops from it rather than from launch and quit.
- Stopping waits for the files, which is the one way this spec could corrupt a recording: disarm
  mid-recording, capture stops, and the file is cut short with no index. Question 4 said to wait
  on `onRecordingsFinished`, and that turned out to be wrong. `disarm()` sets `armedState` to
  `.unarmed` and clears `currentFilePaths` *before* telling the recorders to stop, so when the
  files finish, `recordingDidFinish` returns early on its `isRecording()` guard and the callback
  never fires. On the disarm path there is no completion signal at all; quitting works only
  because it doesn't disarm first. So capture asks its own recorders instead:
  `PreRollRecorder.isWriting` says whether a writer is still open, and the stop retries every
  200 ms until none is. That leaves `RecordingManager` and the quit path untouched.
- `CaptureManager` already has `start()` and `stop()` on `sessionQueue`, and `configureSession` is
  already re-run for device changes, so the machinery exists. What's new is who decides.
- The hooks exist: `AppDelegate.showPopover`/`closePopover`, the preview window's controller, and
  `RecordingManager`'s state changes, which the popover already observes.
- Warm-up was the suspected risk and isn't one. Measured: 856 ms cold, 350 to 370 ms on reopen,
  with the second frame about 1 ms behind the first (question 3). The arming countdown covers it
  many times over, and opening the popover costs a third of a second of flat meters.
- The countdown is the wait, rather than arming blocking on a capture-running signal. `.arming` is
  itself a reason to capture, so pressing Arm starts the session at once, and the countdown is 5
  seconds by hand or 15 at launch against a 350 ms warm-up. Gating the countdown on capture
  actually running would add a state where arming never completes: if the camera is denied or a
  session fails to configure, Arm becomes a dead button. Letting arming finish degrades better,
  since the existing auto-disarm rule already handles nothing being able to trigger.
- Pre-roll is the real cost, and it isn't about warm-up. `PreRollRecorder` can only reach back as
  far as the cameras have been open, so a full pre-roll needs them running for the pre-roll window
  before the trigger. Any trigger soon after capture starts therefore records a short pre-roll,
  whether capture started at a self-arm or at opening the popover. Question 5 accepts that: the
  alternatives all put the cameras back to running while OnCue is not watching.
- The audio meter (`startAudioMeter`) runs on the same session as the video, which is why one rule
  for both is the cheap answer: the sessions start and stop whole.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [x] With OnCue open, unarmed, popover closed: no camera indicator in the menu bar
- [x] Pre-roll is as long as the cameras have been running, up to the setting

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

## Tasks
- [x] The rule for when capture should be running, with tests
- [x] `CaptureManager` starts and stops from it
- [x] Arming starts capture at once; the countdown is the wait
- [x] Stopping waits for a file to finish writing
- [x] Manual checks, Verification filled in

## Verification

**Built, 2026-09-20.** `scripts/check` passes: clean build, 114 tests, no new warnings.

`CaptureDemand` holds both rules and is tested directly: unarmed with nothing open means no
capture; `.arming`, `.armed`, and `.recording` each hold it open; the popover and the preview each
hold it open on their own; closing the popover mid-recording doesn't stop it; and a file still
being written blocks a stop whatever the demand says.

What the work found, which the spec had wrong: question 4 assumed a stop could wait on
`onRecordingsFinished`. It can't. `disarm()` sets `armedState` to `.unarmed` and clears
`currentFilePaths` before calling `stopRecording()` on the recorders, so `recordingDidFinish`
fails its `isRecording()` guard and the callback never fires. The disarm path has no completion
signal at all; the quit path works because it never disarms. Capture asks its own recorders
instead, through a new `PreRollRecorder.isWriting`, and retries the stop every 200 ms until no
writer is open. `RecordingManager` is untouched.

Also deliberate: `reconfigure(camera:)` only restarts capture if something still wants it, so a
camera plugged in while OnCue sits idle reconfigures without opening anything. The audio meter
stops with capture and reports a level of zero, so the popover's sound meter doesn't freeze at its
last reading.

**Manual check, 2026-09-20.** Disarming during a recording leaves a file that plays. That's the
path the spec had wrong, and the one that would have shipped a broken `.mov` if the replacement
signal were wrong too.

The camera indicator is off while OnCue sits unarmed with the popover and preview closed, which is
the point of the spec: a lit camera now means OnCue is watching.

Opening the popover brings the meters up quickly enough not to read as broken, which was the
question behind closing immediately rather than keeping an idle timer.

**Trial, 2026-09-20.** The first attempt at the popover-closed-while-recording check produced a
file with a 24 second hole in its video and audio ending early, on both cameras. A temporary
logging build, since stripped, settled it: closing the popover mid-recording changes nothing.

```
18.172  popover opened          wanted=true  capturing=false
18.173  session START
19.456  START RECORDING targets=2
33.114  state=recording popover=false  wanted=true capturing=true writing=true
44.809  recording ended
```

One `session START` for the whole run and no `session STOP` at all. No refused appends, no input
ever unready. The two recordings came out clean: 25.94 s of video in 774 frames against 26.01 s of
audio, and 15.15 s in 452 frames against 15.20 s, both at 29.8 fps with no gaps. The first is the
one whose popover was closed mid-recording.

The earlier bad file is unexplained and didn't reproduce. The suspicion, unproven, is that the run
was under load and `CameraPipeline` silently skips frames when the encoder falls behind. Whatever
it was, it isn't this spec, and it exposed something worth its own spec: frames can vanish from a
recording and nothing anywhere says so.

**Manual checks, 2026-09-20.** The microphone follows the cameras: no mic indicator while OnCue
sits idle. A trigger immediately after arming still records.

Pre-roll is shorter than the setting whenever a recording starts soon after capture did, and the
logged run measured it: the popover opened at 18.173, the recording started at 19.456, and the
file holds about 0.6 seconds before the trigger rather than 5. The second recording shows the
other limit, already by design: 13.0 seconds recorded in a 15.15 second file, because the previous
recording had ended 3.0 seconds earlier and `PreRollRecorder` won't write footage twice. Both are
accepted, and question 5 now says so rather than claiming the popover path is unaffected.

## Open questions
1. Resolved (Jake, 2026-09-19): one rule for both. Every argument for releasing the cameras
   applies to the mic unchanged, including the indicator meaning "OnCue is open" rather than
   "OnCue is listening", and it means starting and stopping the sessions rather than reconfiguring
   them to mic-only on every popover click. The pre-roll warm-up concern therefore covers audio as
   well as video.
2. Resolved (Jake, 2026-09-19): preview open is a reason on its own, alongside armed and popover
   open. Preview exists to aim the camera and set the sliders, which happens before arming, so it
   would show black exactly when it's needed otherwise. Consequence, accepted deliberately: with
   "Open Preview Window at Launch" on, the cameras open at launch and stay open while the window
   is up, so that setting opts a user out of this spec. That's correct rather than a hole, since
   it's an explicit choice to sit and watch the camera.
3. Resolved (Jake, 2026-09-20): close immediately, no idle delay. Measured on the built-in camera
   with the mic attached: 856 ms to the first frame on a cold start, then 350 to 370 ms on every
   reopen, five runs. A third of a second of flat meters when the popover opens is perceptible but
   not broken, and an idle delay would add a timer and state to save it. The second frame arrives
   about 1 ms after the first, so the motion detector's two-frame requirement costs nothing, and
   the arming countdown covers the warm-up many times over.
4. Resolved (Jake, 2026-09-20): no fourth reason. `ArmState` is `unarmed`, `arming`, `armed`,
   `recording`, so the reason is "the state is anything but unarmed", which covers a recording in
   progress by construction. A separate recording flag could contradict the armed one and stop
   capture mid-recording; deriving all of it from one enum makes that unrepresentable. The care
   is at the end: stopping capture waits for `onRecordingsFinished`, the same signal quitting
   already waits for, because a file cut short has no index and won't open. Disarming during a
   recording is the case that would otherwise break it.
5. Resolved (Jake, 2026-09-20): accept it. Pre-roll can only reach back as far as the cameras have
   been open, so a trigger soon after capture starts records a short pre-roll rather than a full
   one. Something interesting happening in the seconds right after an unattended restart is
   unlikely enough not to design around, and a short pre-roll is a shorter recording, not a missed
   one. The alternatives both reintroduce a window where the cameras run while OnCue isn't
   watching, which is the thing this spec exists to remove.

   This was first written as "arming from the popover is unaffected", and the logged run showed
   that was wrong: the popover opened at 18.173 and the recording started at 19.456, giving about
   0.6 seconds of pre-roll rather than 5. Opening the popover is what starts the cameras, so the
   shortfall applies there too whenever arming follows quickly. It is the same acceptance, just
   stated honestly.
