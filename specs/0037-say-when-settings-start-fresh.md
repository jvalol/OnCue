---
title: Say when OnCue starts with fresh settings
status: shipped
created: 2026-09-22
commits: 5c20ce5 (approval), 0ef731b (implementation), ea0ac1d and f9e0448 (spec), 2040271 (released in 4.8)
---

## Problem
The next release changes the bundle ID from `lol.jva.oncue` to `com.eggdevil.oncue` (`a687db6`, for
the App Store record). Every direct download ever shipped, 4.4 through 4.7.1, is `lol.jva.oncue`,
checked against the zips in `site/downloads`. So for every direct and brew user, the next update is
a new sandbox container, and macOS treats it as a new app:

- Every setting is back at its default: thresholds, pre-roll, timeout, the retention limit, the
  chosen camera and microphone, open the preview at launch.
- The chosen recordings folder is gone. Its bookmark lived in the old container, so recordings go
  back to `~/Movies/OnCue`.
- Open at login and arm at login read as off. `SMAppService.mainApp` registers by bundle ID, so the
  old registration isn't this app's, and `armAtLogin` is a default in an empty container.
- Camera, microphone and notification permission are per bundle ID, so macOS asks again.

The permissions announce themselves the first time capture starts. The rest doesn't. Someone who
set OnCue to arm itself at login updates, and the next morning it isn't armed and nothing said so.
That is the silent-failure shape of the one-star reviews, done to the people who trusted it most.

The app can't fix the reset: the sandbox won't let it read the old container, so there is nothing
to migrate from. What it can do is say so, once, where the person will look.

## Non-goals
- Migrating settings from the old container. Not possible from inside the sandbox.
- Re-registering the login item, or doing anything about the stale `lol.jva.oncue` entry in System
  Settings. What that entry does at the next login is a fact to find (Verification), not something
  this spec acts on.
- Telling the difference between an update and a genuinely fresh install. The app can't see the old
  container, so the notice fires on any first launch and is worded to be true for both.
- The changelog and feed entry for 4.8, which say the same thing in public. Separate copy.
- Cleaning up the old container. The cask's zap stanza names both IDs already.

## Behaviour (acceptance criteria)
- [x] On the first launch into an empty container, the popover's notice line says OnCue is starting
      with default settings and names the two that matter: the recordings folder and arm at login.
      Unit test on the `PopoverNotice` rule; manual check that it shows in the real popover.
- [x] The notice ranks below anything that is happening or has happened (motion detection stopped,
      a gap, a failed recording, a deletion) and above the lid warning. Unit test.
- [x] The notice stays for that launch until Settings has been opened or OnCue has been armed, and
      is never shown on a later launch. Unit test on the rule; manual check across a relaunch.
- [x] A container that already has settings never shows it: an ordinary launch of an installed OnCue
      is unchanged. Unit test.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
**The trigger already exists.** `DetectLaunch.isFirst` in `AppDelegate` is true exactly once per
container, and it's where the first-launch thresholds are written. A fresh start sets a second
default alongside, `freshStartNoticePending = true`, and the popover reads it. Nothing new has to
detect anything.

**The rule is pure.** `PopoverNotice` gains a `.freshStart` case, and `notice(...)` takes
`freshStart: Bool`. Ranking: `motionDetectionStopped` first, then the newest of the things that
happened, then `freshStart`, then `lidWouldStopWatching`. On a first launch nothing has happened
yet, so in practice it shows; the ranking matters only so a real problem later that same session
displaces it. Tests go next to the existing `PopoverNotice` tests.

**Clearing.** `freshStartNoticePending` is set false when Settings opens (`viewWillAppear`, which
0034 already made the refresh point) and when the arm state leaves `.unarmed`. Both mean the person
has looked. It's a stored flag, so a relaunch without either still shows it, and once cleared it
stays cleared. Alternative rejected: clearing when the popover closes, which is exactly the glance
that doesn't read the line.

The arm-side clear lives in `AppDelegate`'s existing observation of the app's `RecordingManager`,
not in `RecordingManager` itself. First attempt put it in the `armedState` `didSet`, and every
arming test disarmed itself: `RecordingManager` watches `UserDefaults.didChangeNotification` on its
own defaults to re-check whether any trigger can fire, and a write from inside the arm transition
trips that. In tests nothing can fire, so the write disarmed the manager it was reporting on. The
observation is synchronous, so the popover's own observer, which redraws asynchronously, always
reads the cleared flag.

**What it says.** One sentence that is true for an update and for a fresh install: settings are at
their defaults, check the recordings folder and arm at login. It must not say "didn't carry over",
because on a fresh install nothing did and the sentence would be a puzzle. Copy is Jake's, marked.

**The notice line wraps.** Decided during implementation (Jake, 2026-09-22). The storyboard had the
notice label as one truncating line and `layOutMotionColumn` never counted it, so a two-line notice
would have been clipped, and the longer existing notices were already losing their ends at the
popover's width. The label now word-wraps with no line limit, `updateNotice` re-lays out after
setting the text, and the height beyond one line goes into the popover's `preferredContentSize` the
same way the trigger cost line does. That changes every notice, not only this one: a long failure
text wraps instead of truncating. The fresh-start copy is two lines, split with a newline.

**Settings needs nothing.** The folder row already tells the truth about the folder in use (0034),
and the arm-at-login box reads the setting, which is off. Both show the reset correctly once the
window is open; the notice is what gets someone to open it.

**What this can't reach.** If the stale login item no longer launches the app, OnCue isn't running
and nothing in it can speak. That case is covered only by the changelog and, for store users, the
release notes. Whether it happens is the manual check below.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [x] The upgrade rehearsal in Verification has been done on this Mac before 4.8's changelog copy is
      written, since its outcome decides whether that copy has to say "turn open at login back on"

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

The notice line: OnCue is starting with default settings; look at the recordings folder and arm at
login in Settings. Short enough for the notice label, which is one line.

## Tasks
- [x] `PopoverNotice.freshStart` and the ranking, with tests
- [x] `freshStartNoticePending` set on first launch, cleared from Settings and from arming
- [x] The popover renders it (marked copy)
- [x] Upgrade rehearsal on this Mac, outcome recorded in Verification

## Verification
- **Built (2026-09-22):** `FreshStart` in `OnCue/Managers/Helpers/FreshStart.swift` holds the stored
  flag, with `UserDefaults` injected so tests use their own suite. `AppDelegate` calls `begin()`
  inside the existing `DetectLaunch.isFirst` block; `SettingsViewController.viewWillAppear` and
  `AppDelegate`'s arm-state observation (see Design for why not `RecordingManager`) call `clear()`. `PopoverNotice.notice(...)`
  takes `freshStart:` and returns `.freshStart` after the things that happened and before the lid
  warning. The popover passes `FreshStart.app.isPending` and renders the marked line; the arm state
  observation it already has is what refreshes the line when arming clears the flag.
- Clean build, 262 tests, 0 failures, 1 skipped, no warnings (2026-09-22). Eight of those are new.
- Unit tests: four in `FreshStartTests` (nothing pending on an ordinary launch, pending after
  `begin()`, survives a new instance on the same defaults, cleared stays cleared) and four in
  `SleepRiskTests` (shows armed or not, outranks the lid warning, every kind of trouble outranks it,
  absent it changes nothing).
- The copy is Jake's, two lines, marker struck 2026-09-22. `scripts/check` green after it.
- **First launch, seen (Jake, 2026-09-22):** a Debug run with `-validateFirstlaunch YES` as a launch
  argument, which makes `DetectLaunch.isFirst` read true without touching the container (Terminal
  can't, TCC guards `~/Library/Containers/*/Data`). The two-line notice showed and the popover grew
  to fit it; the Settings window ended below the folder note.
- **Upgrade rehearsal, done (Jake, 2026-09-22):** 4.7.1 from brew (`lol.jva.oncue`) in
  `/Applications` with open at login and arm at login on; replaced by a Release build of master
  (`com.eggdevil.oncue`, signed for `DC3U4XZMM4`, sandboxed), not launched; log out, log in.
  - **OnCue did not launch.** No menu bar icon. That is the case this spec cannot reach.
  - Login Items showed `OnCue.app` under Open at Login and under Background App Activity, switched
    on. The registration survived the identity change and the switch reads on; it launches nothing.
  - Launched by hand, then Open OnCue at Login ticked in Preferences: Login Items now lists
    **two** `OnCue.app` rows, the dead one and the live one. Nothing in the app can remove the dead
    one; `SMAppService` only reaches the app's own identity, and login items aren't in the container,
    so the cask's zap can't either. It has to be removed by hand, select and minus.
  - The popover on that manual launch showed the lid warning, not the fresh-start notice, because
    the `com.eggdevil.oncue` container on this Mac was not empty: `scripts/check`'s test host had
    created it at 10:59 and the `-validateFirstlaunch` run had used and cleared it. Not a finding
    about the notice; an updater's container has never seen a launch.
  - Restored with `brew reinstall --cask oncue`.
- **What that decides for 4.8:** the changelog, the feed and the store's What's New lead with it:
  after this update OnCue will not open at login until you remove the old OnCue row in System
  Settings > General > Login Items and turn Open at Login back on in OnCue's Preferences, and arm
  at login and the recordings folder need setting again. For brew users the cask gets a `caveats`
  stanza saying the same, which brew prints at the moment of the upgrade; that's the only channel
  that reaches anyone at the right time.
- Not yet done: the real popover on a first launch (which is also where the wrapped height and the
  popover growing to fit get seen), the notice across a relaunch, and the upgrade
  rehearsal. The rehearsal needs a Release build installed over 4.7.1 in `/Applications` and a
  logout, so it is Jake's to run; its outcome goes here and decides 4.8's changelog copy.

Upgrade rehearsal, to do on this Mac before 4.8: install a `lol.jva.oncue` build (4.7.1 from
`site/downloads`) in `/Applications`, choose a non-default folder, turn on open at login and arm at
login. Replace it with a `com.eggdevil.oncue` Release build at the same path. Record: whether OnCue
launches at the next login at all; whether the notice shows; what System Settings > Login Items
lists; whether the camera prompt appears again. The first of those decides the changelog copy.

## Open questions
1. Resolved (Jake, 2026-09-22): Settings opened or OnCue armed, stored, so it survives relaunches
   until one of those happens. "This launch only" loses the person it's for: OnCue launches at
   login, nobody opens the popover that day, and the line is gone before anyone read it. A fresh
   install that never opens Settings keeps seeing it, which is true every time, and the first arm
   clears it.

2. Resolved (Jake, 2026-09-22): no sharper wording. Recordings in `~/Movies/OnCue` would identify
   the updaters on the default folder, who lost the least; the ones with a chosen folder have
   nothing there and would get the plain sentence anyway. One sentence true for everyone, and the
   changelog says "didn't carry over" where it can be certain.

3. Resolved (Jake, 2026-09-22): no notification. Notification permission is reset by the ID change
   too, so posting one makes the system prompt the first thing the app does after an update. And it
   doesn't reach the worst case, where the stale login item doesn't launch the app at all; that one
   is the changelog's whatever happens here.

## Closure
Shipped in 4.8 (2026-09-22). The relaunch check was done on the `-validateFirstlaunch` run: the
line stayed across a quit and relaunch until Settings was opened, then stayed gone. The 4.8
changelog, feed and the cask's `caveats` carry the login-item instruction the rehearsal decided;
the App Store's What's New does not, since store users come from 3.0.3 on the same bundle ID.
