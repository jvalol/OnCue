---
title: Menu bar icon shows the arm state in color
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-19
commits: 374005f (spec), 1fc99b7 (implementation)
---

## Problem
The menu bar icon is the same gray disc whatever OnCue is doing. Knowing whether it's armed, or
recording right now, means opening the popover. The app icon's lens has a red ring and a blue
center that the menu bar never used.

## Non-goals
- Changing the app icon.
- Notifications or sounds for state changes.

## Behaviour (acceptance criteria)
- [x] Unarmed, the icon is monochrome and follows the menu bar's light or dark appearance, as a
      template image does. Manual check in both appearances.
- [x] Arming shows an orange ring, armed the app icon's red ring and blue center, and recording a
      red ring and red center, steady, no pulse. Unit test on the state-to-appearance mapping; manual
      check through a full arm, trigger, and disarm.
- [x] The icon changes as the state changes, including automatic disarms (specs 0003 and 0008).
      Manual check.
- [x] The icon's accessibility label names the current state. Manual check with VoiceOver.
      (A tooltip was dropped: see Verification.)
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- **Drawn, not bundled:** the icon is drawn in code at menu bar size as a ring and a center dot, so
  each state is a color choice rather than another image file, and it stays sharp at any scale.
  Unarmed it's a template image.
- A pure mapping from arm state to ring color, center color, and template or not, unit-tested.
- `AppDelegate` observes `RecordingManager.armedStateRaw` (already KVO-observable) and redraws.
- The tooltip and accessibility label are copy: drafts carry `[COPY - Jake]`.
- **Built (2026-09-19):** `MenuBarIcon.appearance(for:)` maps each state to template or colors;
  `MenuBarIcon.image(for:)` draws an 18-point ring and center dot in system colors. `AppDelegate`
  observes `armedStateRaw` and redraws; the bundled `menu_icon` image is no longer used.
  The accessibility label reuses the popover's shipped state text in Jake's "OnCue - …" format
  ("OnCue - Armed", "OnCue - Arming… 4"), so there's no new copy and no marker.

## Gates
- [x] `scripts/check` passes

## Tasks
- [x] State-to-appearance mapping with tests
- [x] Drawn icon, redrawn on state changes
- [x] Accessibility label (tooltip dropped)
- [x] Manual checks, Verification filled in

## Verification
- `MenuBarIconTests` (3): unarmed is a template; arming, armed, and recording have their colors; no
  two states look alike. 85 tests pass on a clean build with no warnings (`scripts/check`).
- Rendered the four icons at 4x on light and dark backgrounds: all distinct on both.
- Jake's manual checks (2026-09-19): the colors through a full arm, trigger, and disarm, and both
  menu bar appearances, all pass.
- The tooltip was set, and accessibility reported it ("OnCue - Unarmed" as both label and help), but
  macOS never displayed it: most likely because OnCue, a menu-bar-only app, is almost never the
  active app. A custom hover label would work around it, but the colors already carry the state, so
  Jake dropped the tooltip; the accessibility label stays.

## Open questions
Resolved by Jake, 2026-09-19: the proposed colors (orange arming; red ring and blue center armed;
all red recording), and steady red while recording, no pulse.
