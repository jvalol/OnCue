---
title: An accessibility pass
status: shipped
created: 2026-09-23
commits: 1762020 (approval), bd3753f (implementation), 584d1df and 83c456d (built state, manual checks), f182c6e and 7e01e4f (released in 4.22)
---

## Held as a draft (Jake, 2026-09-23), lifted 2026-10-21
Lifted because App Store Connect now shows an accessibility label on the product page (the App
Accessibility section under Trust and Safety), and OnCue can't claim VoiceOver on it honestly
until this is done. Same kind of work as the subtitle and the pictures: listing work that also
makes the app usable without seeing the popover.

Not until someone asks. The gap is scoped below so the work is a half day when they do. The
recordings are visual; operating the app isn't (arming, state, thresholds, notices, the sound
trigger), and the same labels serve Voice Control, Switch Control and keyboard-only use. But
nobody has asked, the store data doesn't say anyone will, and the store listing can say
"partial" truthfully in the meantime.

## Problem
One accessibility label in the app (the menu bar icon) and none in the storyboard. VoiceOver
reads two checkboxes as "Trigger" with nothing to tell sound from motion, two sliders with no
name, three meters as "level indicator" with no value, and the gear as an unnamed button. In
Settings no label is tied to the control beside it, and the schedule's weekday checkboxes read
as single letters. The zone editor is mouse-only.

## Non-goals
- A keyboard path for drawing zones. Its own spec; the whole-frame default works without one,
  and the gap is documented rather than hidden.
- Larger text, contrast or reduced-motion work. Nothing here animates, and the popover uses
  system fonts; checked, not changed.

## Behaviour (acceptance criteria)
- [x] Every control in the popover and Settings has an accessibility label that names it
      (Sound threshold, Motion trigger, Second camera threshold, Monday, the gear), and each
      meter a spoken value ("40 percent"). Unit test that loads both and walks every control.
- [x] Settings labels are the accessibility titles of the controls beside them. Unit test.
- [x] The labels are localized: German for each, and 0043's invariant green. Unit test.
- [x] A VoiceOver walk of the popover, Settings and the preview window, in English and German,
      with every control reachable and named. Manual check, Jake's ears.
- [x] The zone editor's gap stated in the help page. Manual check.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
`setAccessibilityLabel` and `setAccessibilityValueDescription` in `viewDidLoad` for the
popover's controls (the second camera's are made in code already), `setAccessibilityTitleUIElement`
for Settings rows, full weekday names as labels on the schedule's one-letter checkboxes. All
labels through `String(localized:)`. The test walks `view.subviews` recursively and asserts on
every `NSControl` and `NSLevelIndicator`.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [x] The VoiceOver walk

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

Copy to convey: a name for each unnamed control, a spoken value for each meter, one help
sentence saying zones need a mouse.

## Tasks
- [x] Popover: labels on both meters, both trigger checkboxes, both sliders, the second
      camera's meter and slider, the pin button and the gear; a spoken percentage on every meter,
      set whenever a meter moves. New outlets for the two picture-only buttons.
- [x] Settings: each pop-up and number field takes the label beside it as its accessibility
      title (six new label outlets); the path field gets a name; the schedule's weekday boxes
      carry the full day name from the calendar; the pickers and the minus button get names.
- [x] `AccessibilityTests`: walks the real popover and Settings scenes from the storyboard
      inside the app and fails on any control without a name; checks the meters speak their
      level, the weekdays are the calendar's, and the six Settings labels title their controls.
- [x] German for the fifteen new code strings.
- [x] Help: one sentence under zones saying drawing them takes a mouse, under a marker.
- [x] Markers struck (Jake, 2026-10-21), `scripts/check` green.
- [x] The VoiceOver walk (Jake, 2026-10-21).
- [x] Changelog and feed entry for the release, with the disclosure line.

## Verification
- `scripts/check` green on this Mac, 2026-10-21, after the markers were struck: 442 tests, one
  skipped, no failures; the four new `AccessibilityTests` among them.
- Manual checks look good (Jake, 2026-10-21): VoiceOver through the popover, Settings and the
  preview window, in English and German.

## Open questions
1. **What the App Store Connect accessibility section can claim after the pass. Resolved
   (Jake, 2026-10-21):** VoiceOver and Voice Control, once the walk passes, with the zone
   editor's mouse-only drawing as the stated exception; the help page says the same.
