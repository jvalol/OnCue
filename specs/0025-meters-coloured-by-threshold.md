---
title: Colour the meters by the threshold they're being compared against
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-20
commits: 08fd58e (spec), b4777fe (implementation)
---

## Problem
The meters turn yellow at 75 and red at 90, always. Those numbers are hardcoded, in the storyboard
for the sound and motion meters and in `buildSecondCameraControls` for the second camera's, and
they have nothing to do with where the slider underneath is set.

So the colour answers a question nobody asked. A meter sitting red while the threshold is at 25
looks alarming and means nothing is going to happen; a meter still green at 70 with the threshold
at 60 looks calm while a recording is about to start. The only question the meter exists to answer
is whether what it's picking up is enough to trigger, and the colour currently can't tell you.

## Non-goals
- A gradient. `NSLevelIndicator` can't draw one, so it would mean replacing the meters with custom
  layer-backed views and owning the bar, the corner radius, and both appearances. Worth revisiting
  only if the colours still feel wrong once they track the trigger.
- Changing the thresholds themselves, or how motion and sound levels are calculated.
- The preview window's red motion overlay, which is a different thing and already keyed to motion
  rather than to a threshold.

## Behaviour (acceptance criteria)
- [x] A meter is green while what it's picking up wouldn't trigger a recording. Unit test on the
      rule, plus a manual check.
- [x] It's red once the level reaches the threshold, within a point of where it would trigger.
      Unit test, plus a manual check that the colour changes as the app starts recording.
- [x] It's yellow in between, approaching the threshold. Unit test.
- [x] Moving a slider recolours its own meter straight away, without waiting for the next sample.
      Manual check.
- [x] Each meter follows its own threshold: sound, the first camera, and the second camera are
      independent. Manual check with two cameras.
- [x] A threshold at either extreme still produces sensible colours rather than an inverted or
      empty band. Unit test.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- `NSLevelIndicator` already draws green, yellow and red, switching at `warningValue` and
  `criticalValue`. Nothing needs to be drawn; those two numbers just need to follow the slider
  instead of sitting at 75 and 90.
- A pure function turns a threshold into the pair, so the band arithmetic is testable on its own
  and the same rule serves all three meters.
- The three thresholds already live in different places: sound in `audioTriggerThreshold`, the
  cameras in `MotionDetector.threshold(cameraID:)`, which is per camera. The meters are updated
  wherever those are read or written today: the slider actions, and where the popover loads saved
  values.
- The storyboard's hardcoded 75 and 90 come out, since leaving them would decide the colours until
  the first slider move.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [x] With the threshold low, a quiet room's meter is red; with it high, a loud one stays green

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

## Tasks
- [x] The rule turning a threshold into the two band edges, with tests
- [x] Meters follow their own thresholds, including the second camera's
- [x] Take the hardcoded numbers out of the storyboard
- [x] Manual checks, Verification filled in

## Verification

**Built, 2026-09-20.** `scripts/check` passes: 143 tests, one skipped (0022's pre-26.2 path), no
new warnings.

`MeterBands.edges(threshold:)` returns the pair, and the tests check it the way the control will
read it: green below the warning edge, yellow between, red at or above critical. The case that
matters most is that the same level reads differently against different thresholds, which is the
whole point: 60 is red against a threshold of 25, yellow against 70, green against 100.

The extremes are covered rather than assumed. A threshold of 100 leaves nothing red because
nothing can trigger; a threshold of 0 is red throughout because everything does. A loop over
thresholds from -10 to 200 asserts the band is never inverted and the warning edge never goes
negative.

`colourMeters()` applies it to all three meters from the thresholds in force, and each slider also
recolours its own meter as it moves, so the colour changes under the cursor rather than on the
next sample. `devicesChanged` recolours too, since a different camera brings its own threshold.
The storyboard's `warningValue="75" criticalValue="90"` are gone from both meters, and the second
camera's hardcoded pair with them; leaving any of them would have decided the colours until the
first slider move.

Worth recording: one of these tests failed first time, and the test was wrong rather than the
code. It asserted that 60 against a threshold of 70 was green, when 60 is squarely inside the top
quarter below 70 and yellow is correct. Fixed the assertion.

**Manual check, 2026-09-20.** The colours work in the app: sliders recolour their meters as they
move, the three meters follow their own thresholds, and the bands land where the trigger is.

## Open questions
1. Resolved (Jake, 2026-09-20): a proportion of the threshold rather than a fixed distance below
   it. The number to start with is the top quarter, so yellow runs from 0.75 of the threshold up
   to it: at a threshold of 50 that's 37.5 to 50, a band wide enough to read. It scales with the
   setting, and like 0024's numbers it's one line in a tested rule, so it's cheap to move once
   there's a feel for it.
2. Resolved (Jake, 2026-09-20): let the extremes be honest, with no special case. Both detectors
   compare with a strict `>`, so a threshold of 100 means nothing can trigger and an all-green
   meter says so truthfully; a threshold of 0 means anything above silence triggers and all-red
   says that. Special-casing either end would make the meter lie to look balanced.

   One imprecision, written down rather than glossed: `NSLevelIndicator` turns red at values at or
   above `criticalValue`, while the trigger needs to be strictly greater than the threshold. With
   `criticalValue` set to the threshold the meter goes red a fraction before the app would record.
   On a 0 to 100 scale that's one point, and nothing holds a level exactly on the line.
3. Resolved (Jake, 2026-09-20): leave the slider alone. The meter is what moves on its own and
   needs interpreting; the slider is set and read off by position. Colouring both would say the
   same thing twice, and `NSSlider` would need custom drawing, which is the cost this spec avoids
   by staying with the native level indicator.
