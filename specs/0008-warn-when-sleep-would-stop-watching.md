---
title: Warn when sleep would stop OnCue watching
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-19
commits: c8097a2 (spec), f26ecbd (implementation)
---

## Problem
While armed, OnCue keeps the Mac from idle sleep (keep-awake, 2026-09-19), but closing a laptop's
lid still sleeps the Mac unless it's in clamshell mode (on power with an external display). Capture
stops, USB cameras lose power, and nothing records. Nothing tells the user this will happen,
or that it did.

## Non-goals
- Preventing lid-close sleep. macOS doesn't allow an app to.
- Warning about sleep the user starts on purpose from the Apple menu.
- Desktop Macs, which have no lid.
- A "don't ask again" option on the arm confirmation, until the confirmation has been tried.

## Behaviour (acceptance criteria)
- [x] While arming or armed on a laptop that would sleep if the lid closed (on battery, or with no
      external display), the popover shows a warning saying so. The warning goes away when that's no
      longer true (power and a display connected) or when disarmed. Unit test on the rule; manual
      check by unplugging power while armed.
- [x] If the Mac slept while armed, then after it wakes the popover says OnCue wasn't watching,
      from when to when, until the next disarm. Unit test on the wording's inputs; manual check:
      arm, close the lid, reopen.
- [x] After waking with a gap, a macOS notification says the same thing, so it's seen without
      opening the popover. OnCue asks for notification permission the first time it arms; if
      permission is refused, the popover line still appears. Manual check.
- [x] Pressing Arm while the risk is present asks for confirmation first, saying that closing the
      lid will stop recording. Confirming arms; cancelling doesn't. With no risk, Arm arms straight
      away as today. Manual check.
- [x] Nothing is shown on a desktop Mac, or while unarmed. Unit test.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- **Why not warn at the moment of sleep:** `NSWorkspace.willSleepNotification` arrives with the
  lid already shut, so nobody would see a warning. The useful moments are before (while armed and at
  risk) and after (on wake).
- **The rule:** a pure `SleepRisk` function of whether the Mac has a lid, whether it's on external
  power, and whether an external display is connected. Laptop from the internal battery in
  `IOPSCopyPowerSourcesInfo`; power source from `IOPSGetProvidingPowerSourceType`; external display
  from `CGDisplayIsBuiltin` over the active displays. Re-checked on power-source and
  display-configuration changes.
- **The gap:** `RecordingManager` notes `willSleepNotification` and `didWakeNotification` times
  while not unarmed, and keeps the last gap until disarm.
- **Notification:** `UserNotifications`; authorization requested on the first arm, posted on wake
  when a gap was recorded.
- **Arm confirmation:** an `NSAlert` from the popover's Arm action when `SleepRisk` says the Mac
  would sleep with the lid closed.
- **UI:** one line under the arm state in the popover, for either message. The warning and the gap
  message are copy: drafts carry `[COPY - Jake]` and must say plainly that closing the lid stops
  recording, and when OnCue wasn't watching. The notification text and the confirmation's message
  and buttons are copy too.

- **Decisions while building (2026-09-19):**
  - `PopoverNotice.notice(armed:lidRisk:gapStart:gapEnd:)` picks the line, and a gap outranks the
    warning since it already happened. Tests cover the choice, never the wording, so Jake's edits to
    the copy can't break them.
  - An internal battery stands in for "has a lid". Power changes arrive through
    `IOPSNotificationCreateRunLoopSource`, display changes through
    `NSApplication.didChangeScreenParametersNotification`.
  - Only the latest gap is kept; a second sleep while armed replaces the first.
  - The notice line always takes its height, so the popover doesn't jump when it appears; the
    popover is 18 points taller.

## Gates
- [x] `scripts/check` passes
- [x] Manual checks on this MacBook Pro

## Tasks
- [x] `SleepRisk` rule with tests; power and display inputs, re-checked on change
- [x] Sleep and wake gap in `RecordingManager`, with tests
- [x] Popover line for the warning and the gap
- [x] Notification on wake after a gap, with permission requested on first arm
- [x] Arm confirmation while the risk is present
- [x] Manual checks, Verification filled in

## Verification
- `SleepRiskTests` (6): laptop on battery or without a display is at risk, clamshell mode isn't, a
  desktop never is; nothing shows unarmed, the warning shows armed with the risk, a gap outranks the
  warning. `RecordingManagerTests` adds 3: a gap recorded while armed, none while unarmed, cleared on
  disarm. 54 tests pass on a clean build with no warnings; `scripts/check` passed in full once Jake
  had the copy markers struck.
- The monitor's inputs on this MacBook Pro: internal battery yes, AC power yes (matching `pmset`),
  external display no (only the built-in "Color LCD"), so it reports the lid risk, correctly.
- Jake's manual checks (2026-09-19): all pass. He found the arm confirmation on every arm adds
  friction; its replacement is a follow-up spec.

## Open questions
Resolved by Jake, 2026-09-19:
- Post a notification too, not just the popover line.
- Try asking for confirmation before arming while the risk is present, to see how it feels.
