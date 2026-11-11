---
title: Warn when Edge Light is lighting the room OnCue is watching
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-19
commits: 51bc3c7, ec186e3, a29d5c7 (spec), d89a16d (implementation)
---

## Problem
macOS 26.2 has Edge Light, which lights the screen's edges to illuminate whoever is in front of
the camera. It engages whenever an app holds a supported camera, so it engages for OnCue, and the
first thing Jake saw running the 4.0 download was his screen glowing.

For a security camera that matters three ways. It lights the room being watched, which is the
opposite of unobtrusive. It changes the scene between camera use and no camera use, and a
brightness change in front of a frame-diff detector is exactly what OnCue is built to notice. And
a glowing screen announces that the Mac is watching.

OnCue cannot turn it off. `isEdgeLightEnabled` and `isEdgeLightActive` are read-only, there's no
control mode like Center Stage's, there's no Info.plist opt-out like Studio Light's, and every
format on the built-in camera supports it. What OnCue can do is say it's happening, the way it
already warns that closing the lid would stop it.

## Non-goals
- Turning Edge Light off, or pretending to. It's the user's switch and we can't reach it.
- Releasing the cameras while idle so Edge Light never engages unarmed. That's the larger change
  this problem suggests, and it's its own spec.
- A notification. This is a standing condition, not an event, and the popover line is enough.
- The other camera effects. Center Stage, Portrait, Studio Light, and Reactions are all off here
  and none of them light the room.

## Behaviour (acceptance criteria)
- [x] While Edge Light is active, a line at the bottom of the Motion column says the screen is
      lighting the room. Unit test on the rule, plus a manual check with Edge Light on.
- [x] Turning Edge Light off clears the line while the popover stays open. Manual check.
- [x] The existing notice line under the arm state is untouched: the lid warning and the sleep-gap
      notice behave exactly as before. Unit test (the existing `PopoverNotice` tests still pass
      unchanged).
- [x] With no camera, the line can't appear, since there's nothing for Edge Light to attach to.
      Unit test.
- [x] On macOS before 26.2 nothing changes and the line can never appear. Unit test on the rule
      with the flag false; the availability check itself is at the call site.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- The line belongs to the Motion column, not to `PopoverNotice`. That rule and its tests stay
  exactly as they are: the lid warning and the sleep gap keep the one line under the arm state,
  and this is a second, smaller line on the side of the popover responsible for it. Whether it
  shows is still a pure function, taking whether Edge Light is active and whether there's a
  camera at all, so it's testable without the popover.
- It goes at the *bottom* of the Motion column, below the last threshold slider shown, rather than
  under the camera name as first written. The two columns are matching stacks of name, meter,
  checkbox, slider; a line between Motion's name and its meter would push Motion's meter, checkbox
  and slider below Sound's and the columns would stop lining up. The bottom of the column already
  grows and shrinks, since the second camera's controls appear there and `armedTextField`
  re-anchors to whichever slider is last, so this extends a pattern rather than fighting one. The
  cost is another permutation in that constraint juggling, with and without a second camera.
- One line, not one per camera. `isEdgeLightActive` is a class property and says nothing about
  which device it applies to.
- The flag comes from `AVCaptureDevice.isEdgeLightActive`, behind `if #available(macOS 26.2, *)`
  and false otherwise. The deployment target is macOS 14, so this has to compile and behave on
  systems that have never heard of Edge Light.
- Keeping it current is the open risk. Apple documents both Edge Light class properties as
  key-value observable, but KVO on a class property from Swift is awkward, and `SleepRiskMonitor`'s
  pattern of a `@objc dynamic` stored property with its own notifications doesn't map onto it. The
  cheaper path is reading the value when the popover refreshes, which it already does while open.
  Whichever way, the warning has to clear without reopening the popover.
- Copy: the line says the screen is lighting what OnCue is watching, and that it is a macOS
  setting rather than something OnCue controls. It names no path for turning it off, because we
  could not confirm one.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [x] Manual check on this Mac with Edge Light switched on and then off, popover open throughout

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

## Tasks
- [x] Decide where the line lives (Open questions)
- [x] The rule for whether the line shows, with tests
- [x] Read `isEdgeLightActive` behind an availability check, and keep it current
- [x] The line in the Motion column, built in code beside the second camera's controls
- [x] Manual checks, Verification filled in

## Verification

**Built, 2026-09-20.** 118 tests, one skipped, no failures and no new warnings. The skip is
`testOlderSystemsNeverWarn`: this Mac has Edge Light, so the pre-26.2 branch of `EdgeLight.isActive`
can't be exercised here. What is tested is the rule it feeds: no warning when it's off, none
without a camera, one when both hold.

`EdgeLight` is a small enum: `isActive` reads `AVCaptureDevice.isEdgeLightActive` behind
`#available(macOS 26.2, *)` and returns false otherwise, and `shouldWarn(active:hasCamera:)` is
the pure rule. `PopoverNotice` is untouched, so the lid warning and the sleep gap keep the notice
line to themselves and their tests pass unchanged.

Two things decided while building rather than in the spec. The line went to the bottom of the
Motion column instead of under the camera name, because the two columns are matching stacks and a
line between Motion's name and meter would have pushed Motion's controls below Sound's. And it's
built in code rather than the storyboard, following the second camera's controls, since like them
it appears and disappears and the arm state has to re-anchor around it.

Keeping it current is the part with no clean answer. Apple documents the Edge Light class
properties as key-value observable, but there's no practical way to observe a class property from
Swift, and `SleepRiskMonitor`'s pattern doesn't map onto one. So the check rides on the motion
meter, which reports per frame while a camera is open, which is exactly when Edge Light can be on.
`updateEdgeLightWarning` returns immediately unless the answer changed, so the cost is a bool
comparison per frame.

**Manual check, 2026-09-20.** The line reads right in the popover, and it clears when Edge Light
is switched off without reopening it, so riding on the motion meter is good enough in practice.

## Open questions
1. Resolved (Jake, 2026-09-19): moot for this line. The warning goes on the Motion side, not the
   shared notice line, so it never competes with the lid warning. Had they shared a line, the lid
   warning would have won.
2. Resolved (Jake, 2026-09-19): the warning lives in the Motion column, not under the arm state.
   Where in that column was settled while building: the bottom, see Design.
   Both original options were wrong. Warning only while armed leaves the glow
   unexplained, since OnCue opens the camera at launch and that is what turns Edge Light on;
   warning always in the shared line makes the one permanent line into noise. Putting it beside
   the camera that causes it reads as OnCue owning the effect, and costs a second warning
   mechanism in a popover that has had one.
3. Resolved (Jake, 2026-09-19): no path. The line says what is happening and stops. Claude
   couldn't find the toggle (Control Center showed only a privacy panel, for OnCue and for
   FaceTime, and System Settings has no entry); Jake found it inside FaceTime's own menus. Naming
   a path we can't confirm is worse than naming none.
