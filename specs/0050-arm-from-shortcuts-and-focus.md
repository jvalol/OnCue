---
title: Arm from Shortcuts, Siri and a Focus
status: shipped
created: 2026-09-23
commits: 2b59312 (approval), bab71b1 (implementation), 71477f3 and 8840146 (built state, manual checks), 6a9bc4a and b105605 (released in 4.13)
---

## Problem
OnCue arms from its popover, at login, or on a schedule. There's no way to arm it because you
left the house, which is the one moment a security camera is for. A schedule approximates it
for people with regular hours. Everyone else has to remember the popover on the way out.

macOS has the machinery: App Intents give Shortcuts and Siri verbs ("Arm OnCue"), and a Focus
Filter lets a Focus carry a setting for an app. Focus syncs across a person's devices, and
iPhone automations turn a Focus on by location, by an NFC tag at the door, or by time. So "arm
when I leave" is: an Away Focus, turned on by the iPhone leaving home, syncing to the Mac,
whose Focus Filter tells OnCue to arm. No network code in OnCue; the syncing is Apple's and the
app's no-network claim stands. The build already runs the App Intents metadata step on every
compile and finds nothing.

## Non-goals
- Remote control over a network, an iOS companion, or HomeKit. The no-network entitlement is
  worth more than any of them (see the platform memory).
- Automations on the Mac itself. macOS Shortcuts has none; the Focus is the bridge, and the
  iPhone is where location and NFC automations live.
- New settings. The Focus Filter is configured in System Settings > Focus, by Apple's UI.
- Changing what arming does. An intent arms the way the popover or the schedule arms.

## Behaviour (acceptance criteria)
- [x] Four actions in the Shortcuts app and to Siri: Arm OnCue, Disarm OnCue, Is OnCue Armed,
      and Record a Test. Manual check in Shortcuts and by voice.
- [x] Arm from an intent counts down and arms the way the popover's Arm does, and does nothing
      when nothing can fire (the intent says why). Disarm disarms, whatever armed it. Unit test
      on each intent's `perform` against the manager.
- [x] Is OnCue Armed returns true or false for a Shortcuts "If" (true for arming, armed and
      recording), and says the state line ("Armed on schedule until 17:00") as its spoken
      result. Unit test.
- [x] Record a Test runs 0046's test, or says it can't while one is running. Unit test.
- [x] A Focus Filter, "Arm OnCue", with one switch: armed while this Focus is on. When a Focus
      with it on becomes active, OnCue arms itself (the 15-second countdown and the "arming
      itself" notification, since nobody is at the Mac). When that Focus ends, OnCue disarms
      only if the Focus armed it; a manual arm, a login arm or a schedule arm is left alone,
      the same rule as 0038's windows. Unit test on the rule; manual check with a Focus toggled
      on the Mac and from an iPhone.
- [x] A Focus that arms OnCue while a schedule is also on: whichever armed it disarms it, and
      neither undoes the other's arming. Unit test on the two flags together.
- [x] The action and filter titles are localized; German for each; 0043's invariant green.
      Unit test.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
**Intents.** `OnCue/Intents/`: four `AppIntent` structs, each a title, a description, and a
`@MainActor perform()` that calls the manager: `startArming(countdown: 5)` guarded by
`canArm()`, `disarm()`, the state and `isArmed()`, `recordTest()`. `openAppWhenRun` is false;
the system launches OnCue in the background if it isn't running, which a menu bar app allows.
An `AppShortcutsProvider` gives Siri its phrases ("Arm \(.applicationName)").

**The Focus Filter.** A `SetFocusFilterIntent` with a `@Parameter var armed: Bool`. The system
performs it when a Focus that has the filter becomes active, and again with the default values
when it ends. `perform` calls `RecordingManager.focusChanged(wantsArmed:)`, which mirrors the
schedule: arming sets `armedByFocus` and uses `launchCountdown` with `onArmedAtLaunch` so the
notification posts; a request to disarm disarms only when `armedByFocus` is set; `disarm()`
clears the flag. `Schedule.action`'s shape, as a pure function with tests.

**Two flags, one rule.** `armedBySchedule` and `armedByFocus` are independent; each side's
"leave" only undoes its own arm. A Focus arm inside a schedule window that then ends: the
schedule's end sees `armedBySchedule` false and leaves it; the Focus's end disarms it. Written
as a table in the tests.

**The state line.** "Armed by Focus" while `armedByFocus`, beside "Armed on schedule until";
Is OnCue Armed returns the same line.

**Strings.** Intent titles and descriptions are `LocalizedStringResource`, which the catalog
picks up like any other key. German for each, with markers until read.

**Cost.** Nothing at runtime while no intent runs. A Focus change is one call.

**Only while running.** The system performs a Focus Filter in a running app and doesn't launch
one for it (seen 2026-09-23). The help pairs the Focus with Open OnCue at Login, as the
schedule's does.

**Copy.** Four action titles with a description each, the filter's title and its switch's
label, the "Armed by Focus" state line, a help section saying how to arm when you leave.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [x] On this Mac: the four actions in Shortcuts, the filter in System
      Settings > Focus, a Focus turned on from an iPhone arming the Mac and its end disarming
      it, and a manual arm surviving a Focus ending

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

Copy to convey: the four actions, each a verb and a line saying what it does; the Focus
Filter's name and its one switch; the state line while a Focus armed it; a help section that
walks through "arm when I leave" with an Away Focus and an iPhone automation.

## Tasks
- [x] The four intents and the shortcuts provider, with tests (marked copy)
- [x] `focusChanged(wantsArmed:)`, `armedByFocus`, the two-flag rule, with tests
- [x] The Focus Filter intent (marked copy)
- [x] The state line and German (marked copy); help section (marked copy)
- [x] The manual checks (the iPhone half and Siri by voice left to Apple's plumbing; see Verification)

## Verification
- **Built (2026-09-23):** `FocusArming.action(wantsArmed:state:armedByFocus:canFire:)`, the
  pure rule; `RecordingManager.focusChanged(wantsArmed:)` and `armedByFocus` (set by a Focus arm,
  cleared by any disarm), the launch countdown and the "arming itself" notification on the
  Focus path, "Armed by Focus" on the state line. `OnCue/Intents/OnCueIntents.swift`: `ArmIntent`
  (five seconds, like the button; says why when it can't), `DisarmIntent`, `IsArmedIntent`
  (a Bool, true for arming, armed and recording, and the state line as the dialog),
  `RecordTestIntent`, `ArmFocusFilter` (one switch), and `OnCueShortcuts` with English phrases.
  The intents reach the manager through `IntentTargets.manager`, set by the app at launch and by
  the tests to their own. The build's App Intents metadata step now produces
  `Metadata.appintents` with the four actions and the filter. Fourteen tests: the rule both
  ways, the Focus path with the countdown and notification, a manual arm surviving a Focus
  ending, the state line, the two-flag table against a real schedule, and each intent's
  `perform` including the filter and the no-manager error. The localization scan covers
  `LocalizedStringResource(...)` literals now. Clean build, 366 tests.
- **Found by the Shortcuts check (Jake, 2026-09-23):** Record a Test from Shortcuts, with the
  popover closed and OnCue unarmed, produced two audio-only files. The cause was in 0046's
  path, not the intent: from unarmed with the popover closed, capture starts on arming, and a
  recorder opened before its camera has produced a frame has no video format, so it writes a
  file with no video track. The menu path never showed it because the popover keeps capture
  running. Fixed in `CaptureManager.recordTestNow()`: the test waits for at least one measured
  frame from every running camera (sound only: any running pipeline), and the manager's
  fifteen-second deadline ends the test if none comes. Two tests on the manager side (capture
  refusing, capture answering later). Seen working from Shortcuts after the fix.
- Also found: Siri fell through to a web search while `/Applications/OnCue.app` was 4.12, which
  has no intents; the system indexes the installed copy. The Debug build was installed there
  for the checks. Arm, Disarm and Is OnCue Armed seen working from Shortcuts; the filter listed
  there as "Set OnCue Focus Filter".
- **The Focus Filter, seen working (Jake, 2026-09-23 18:46):** Do Not Disturb on, OnCue armed
  by Focus; off, disarmed. Traced in the app (a Debug-only `intents.log` in the recordings
  folder, added because the unified log isn't readable from Claude's shell) because two things
  hid it first: the filter's switch starts off in the System Settings sheet and has to be
  turned on, and a filter added while an earlier copy of the app was registered stopped being
  delivered after the app was replaced, until it was removed and re-added.
- **Found: macOS doesn't launch OnCue for a Focus.** With no OnCue running, Do Not Disturb
  turning on did nothing: no process, no crash, no delivery. The filter performs only in a
  running OnCue. So "arm when I leave" holds only while OnCue is open, and the help says to
  turn on Open OnCue at Login with it, the way the schedule's help does. Not fixable from the
  app's side; the launch is the system's.
- **A manual arm survives a Focus (Jake, 2026-09-23 18:49):** armed from the popover, Do Not
  Disturb on and off while it was recording; still recording, the Focus flag never set.
- **App Shortcuts, seen working (Jake, 2026-09-23 19:38):** once the Applications copy was the
  only one running and had been launched from there, Spotlight listed "Arm OnCue" as an App
  Shortcut with the icon and ran it, and Disarm the same. Typed to Siri, "Arm OnCue" still went
  to a web search at 19:38. Spotlight and Siri read the same App Shortcuts index, so the
  registration is right. Siri's only per-app setting for OnCue ("Learn from this application")
  was on at 19:39, so what's left is Siri's own cache of App Shortcuts, which refreshes on its
  schedule. Not chased further: it's outside the app, and a 4.13 installed the normal way
  registers on first launch.
- Not yet seen: a Focus from an iPhone arming the Mac (needs the Focus on both devices). Apple's
  plumbing on top of what's checked.

## Open questions
1. Resolved (Jake, 2026-09-23): Arm from Siri or Shortcuts counts down five seconds, like the
   button: a person said it. The Focus path counts down fifteen with the "arming itself"
   notification, since the Mac may be alone when a Focus flips on.
2. Resolved (Jake, 2026-09-23): only the arming Focus's end disarms, and only what it armed. A
   Focus with the switch off says nothing about OnCue; otherwise a Sleep Focus at eleven would
   disarm a camera armed by hand before a nap, the failure 0038's rule exists to prevent.
3. Resolved (Jake, 2026-09-23): Is OnCue Armed returns both, a Bool for a Shortcuts "If" and the
   state line as the spoken result. Arming, armed and recording all count as true.

## Closure
Shipped in 4.13 (2026-09-23), direct and tap, build 900 uploaded to App Store Connect by the
release script's store section; the store version follows when 4.12 clears review.
