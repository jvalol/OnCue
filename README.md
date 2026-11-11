# OnCue

A macOS menu bar app that watches through your Mac's camera and microphone and
records when something happens. Set how much motion or sound it takes, arm it, and it records while
there's activity.

It's a small security camera: reliability while nobody's there matters more than
features.

- **Motion, sound, or both.** Each trigger has its own meter, threshold, and switch.
- **Pre-roll.** Recordings start a few seconds before whatever set them off, five by
  default and up to thirty.
- **Two cameras.** Your Mac's camera and a USB webcam at once, each with its own
  sensitivity, each recording its own file.
- **Recordings you can find.** Files are named for when they start and the devices
  they came from, saved to `~/Movies/OnCue` or any folder you pick.
- **It stays awake while armed,** warns you when closing the lid would stop it, and
  says afterwards if the Mac slept anyway.
- **It can open at login and arm itself,** so a Mac that restarts goes back to
  watching.
- **Nothing leaves your Mac.** No account needed, nothing up in the cloud. In fact there are no network connections **at all**.

The site is at [oncue.jva.lol](https://oncue.jva.lol), built from
`site/` in this repo.

## Building it yourself

You need macOS 14 or later and Xcode 27. There are no dependencies and no package manager: clone
the repo and build.

Xcode 27 no longer bundles the Metal compiler, and OnCue's motion detection is a Metal shader, so
install that component once:

```bash
xcodebuild -downloadComponent MetalToolchain
```

Then open `OnCue.xcodeproj` and run. Signing is set to a team that isn't yours, so pick your own
under Signing & Capabilities for both the OnCue and OnCueTests targets, or set Team to None and
Signing Certificate to "Sign to Run Locally". The sandbox needs the camera, microphone, and
user-selected file entitlements that are already in `OnCue.entitlements`.

macOS will ask for camera and microphone access the first time OnCue uses them. OnCue is a menu bar
app: it has no Dock icon and no window at launch, so look for its icon in the menu bar.

From the command line:

```bash
scripts/check     # the gate: copy check, clean build, unit tests
scripts/ship-check  # the copy check on its own
```

`scripts/check` builds with signing off and puts `CFBundleVersion` back afterwards, since a build
phase increments it.

## The code

- `OnCue/Managers/CaptureManager.swift` runs one or two `CameraPipeline`s, picks devices, and
  handles cameras and microphones coming and going.
- `OnCue/Managers/CameraPipeline.swift` is one camera: its capture session, the Metal frame diff
  that finds motion, and continuous H.264 compression for pre-roll.
- `OnCue/Managers/PreRollRecorder.swift` keeps the last few seconds in memory and writes files with
  `AVAssetWriter`.
- `OnCue/Managers/RecordingManager.swift` is the arm, countdown, and record state machine, plus
  keep-awake and the rules about when anything can trigger.
- `OnCue/Popover/`, `OnCue/Settings/`, `OnCue/Preview/` are the menu bar popover, Settings, and the
  preview window.
- `OnCueTests/` holds the unit tests: the pure rules (thresholds, device choice, file names,
  pre-roll windows) rather than anything needing a camera.

## How this repo works

Changes that add a capability, change behaviour, or add UI start as a spec in
[`specs/`](specs/README.md), approved before any code and kept accurate as it lands.
[`CLAUDE.md`](CLAUDE.md) has the working rules, the gate, and a map of the code.
