# Specs

Changes that add a capability, change behaviour a user relies on, or add UI start here, as a
short written spec that Jake approves before implementation. The spec stays accurate as the
work lands and remains the durable *why* behind the diff.

This repo's history starts with a single commit. The commits that older specs name by hash are in
a private archive and don't resolve here; the specs themselves are complete.

## How it works

- One spec per change: `specs/NNNN-slug.md`, zero-padded and sequential. The number is the handle.
- Copy [`templates/feature.md`](templates/feature.md), or use `/spec-new`.
- Loop: draft → Jake approves (`status: approved`) → implement with `/spec-implement` → close
  (`status: shipped`, commits listed, Verification filled in).
- Each acceptance criterion maps to a unit test, or to a named manual check when it needs a real
  camera, the menu bar, or sleep behaviour that tests can't reach.
- `/spec-list` shows what's in flight.

## Deliberately unchecked

Manual checks that were decided against rather than forgotten, so they don't sit as open boxes
nobody reads. `[~]` in a spec means this. Nothing here is a plan, and nothing here is owed any
work: each one is a bridge to cross if it ever comes up in the real world. If one of these ever
matters, it'll be because something it covers has gone wrong, and then this list says where to
look first.

- **0029**, the rolling window: the stop threshold saying so in the popover, the Settings field
  saving and reading back, a deletion saying so, and an armed session with the limit at 0 deleting
  nothing. The rules are unit tested; the wiring to the interface is not.
- **0030**, motion detection stopping: sound still watching through an outage, the affected
  camera's meter greying while its slider stays live, and a real camera recovering. All three need
  a GPU texture cache or compute pipeline to fail on demand, and a fake convincing enough to test
  is harder than what it would be testing.

- **0031**, the disk promises during a recording: a deletion mid-recording saying so, and a long
  recording against a low limit rolling and trimming for real. Hours of footage for signal the unit
  tests already give.

The shape is the same in all three: the pure rules have tests, and what nobody has watched is the
wiring from those rules to what a user sees.

## What needs a spec

The line is capability, not size. A new feature, a setting, UI, or a change to what gets recorded
or when gets a spec even if it's an hour's work. A bug fix is a failing test plus the fix, no
spec. Mechanical work (warnings, renames, dependency or tooling bumps) skips it too. When a bug
fix also makes a real design choice, a five-line spec is cheap insurance.

## Status vocabulary

`draft` → being figured out · `approved` → Jake agreed the what · `shipped` → landed ·
`abandoned` → dropped (keep the file, note why).

## Index

Maintained by `/spec-new`; `/spec-list` reads the files directly if this drifts.

| #    | Title                   | Status |
|------|-------------------------|--------|
| 0001 | Spec-driven development | shipped |
| 0002 | Audio level meter and audio trigger, with per-trigger toggles | shipped |
| 0003 | Keep recording through a camera switch | shipped |
| 0004 | Pick up reconnected devices and remember the chosen camera | shipped |
| 0005 | Choose the microphone in Settings | shipped |
| 0006 | Preview window title names the camera | shipped |
| 0007 | Popover headers name the devices in use | shipped |
| 0008 | Warn when sleep would stop OnCue watching | shipped |
| 0009 | Recording file names include the devices used | shipped |
| 0010 | Show recordings from the popover menu | shipped |
| 0011 | Lid warning replaces the arm confirmation | shipped |
| 0012 | Watch two cameras at once | shipped |
| 0013 | Pre-roll: recordings include the seconds before the trigger | shipped |
| 0014 | Menu bar icon shows the arm state in color | shipped |
| 0015 | Open at login | shipped |
| 0016 | Revive the OnCue marketing site | shipped |
| 0017 | Choose where recordings are saved | shipped |
| 0018 | Arm at login | shipped |
| 0019 | Say what's happening when quitting during a recording | shipped |
| 0020 | Ship a downloadable release | shipped |
| 0021 | Label the Settings device pickers, and let there be no first camera | shipped |
| 0022 | Warn when Edge Light is lighting the room OnCue is watching | shipped |
| 0023 | Release the cameras when nothing needs them | shipped |
| 0024 | Say when frames are being dropped from a recording | shipped |
| 0025 | Colour the meters by the threshold they're being compared against | shipped |
| 0026 | Tell people a newer OnCue exists | abandoned |
| 0027 | Say when a recording failed | shipped |
| 0028 | Let Settings choose no microphone | shipped |
| 0029 | Keep recordings from filling the disk | shipped |
| 0030 | Say when motion detection stops working | shipped |
| 0031 | Keep the disk promises during a recording, not only between them | shipped |
| 0032 | Choose the recording resolution in Settings | abandoned |
| 0033 | Say what the trigger is costing | shipped |
| 0034 | Make Settings tell the truth about the recordings folder | shipped |
| 0035 | Make OnCue fail on purpose | abandoned |
| 0036 | Ship to the App Store from the same archive | shipped |
| 0037 | Say when OnCue starts with fresh settings | shipped |
| 0038 | Arm on a schedule | shipped |
| 0039 | Choose the recording quality | abandoned |
| 0040 | Show motion in the preview as a translucent overlay | shipped |
| 0041 | Skip the preview picture when nothing is showing it | shipped |
| 0042 | Watch only the parts of the picture you choose | shipped |
| 0043 | Speak German | shipped |
| 0044 | Stay awake while the schedule is on | shipped |
| 0045 | Say when OnCue quit unexpectedly, and go back to watching | shipped |
| 0046 | Record a test | shipped |
| 0047 | Settings out of the storyboard | draft |
| 0048 | The engine as a package | draft |
| 0049 | An accessibility pass | shipped |
| 0050 | Arm from Shortcuts, Siri and a Focus | shipped |
| 0051 | Say when the schedule can't survive a restart | shipped |
| 0052 | Count downloads and site visits, and show them on a private dashboard | shipped |
| 0053 | A still beside every recording | shipped |
| 0054 | Say what happened while OnCue was armed, and show it | shipped |
| 0055 | A time-lapse of what happened while armed | shipped |
| 0056 | Two cameras side by side in the time-lapse | shipped |
| 0057 | The App Store listing follows each release from the repo | shipped |
| 0058 | Say what changed after an update, with the changelog | shipped |
| 0059 | The dashboard ignores its owner | abandoned |
| 0060 | Say when arm-at-login can't survive a restart | shipped |
| 0061 | An App Store preview, drawn by the app | approved |
