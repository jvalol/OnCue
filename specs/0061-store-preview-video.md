---
title: An App Store preview, drawn by the app
status: approved
created: 2026-11-09
commits: 0e6daa7 (approval), 2773fa1 (the pictures' faults), 57dbede (implementation)
---

## Problem
The store listing has three slots for preview videos and uses none. A preview autoplays in search
results and at the top of the product page, which is where OnCue's one page view a day arrives,
and a thirty-second clip says what seven still pictures can't: that arming counts down, that the
meters move, that something happens over time. Every other camera app on the Mac has one. The
pictures are already drawn by the app itself (0057), so the store shows OnCue as it is; a preview
made by hand in a screen recorder would go stale the same way the hand-made pictures did.

## Non-goals
- Audio, narration or music. Captions carry the words; most people see previews muted.
- More than one preview. Three slots exist; one clip that's true is enough.
- Showing the camera's picture. The render runs without a camera (0057), and the popover doesn't
  show the picture anyway. The preview window stays out for the same reason.
- Playing a finished time-lapse. That happens in QuickTime, not in OnCue, and App Review's rule
  for previews is screen capture of the app itself with text overlays. The clip can show the
  menu item and the popover line that lead to one; the movie itself is not OnCue's screen.
- Localized previews. German follows the same rule as the rest of the listing (memory:
  localization waits for demand).

## Behaviour (acceptance criteria)
- [x] A Debug build launched with `-renderStorePreview <folder>` writes one movie, 1920 by 1080,
      H.264, 30 frames a second, no audio track, between 15 and 30 seconds long, and quits. The
      store script's self-test reads the file's size and duration back (`mdls`) and fails outside
      those bounds. Unit test on the script; manual check that it plays.
- [x] The clip is a sequence of scenes from the same popover the screenshots use, with the same
      state hooks: unarmed, the arm click, the countdown, armed with the meters moving, a
      recording, and the line that counts the stretch and names Show What Happened. Each scene
      carries one caption. The sequence is a pure value (scene, seconds, caption) that a unit test
      checks adds up to the duration and never leaves a frame without a state.
- [x] `scripts/store --preview` builds a Debug OnCue, runs the render and writes the movie into
      `site/store/preview/`, the way `--screenshots` does for the pictures. Manual check.
- [x] `scripts/store <version>` uploads the movie to the version's desktop preview set when its
      checksum differs from what the store holds, deletes a preview the folder no longer has, sets
      the poster frame, and waits for Apple's processing to finish before it submits; a failed
      processing stops the run and says why. A dry run prints the plan. Unit test on the
      reconciliation (the screenshots' `screenshot_plan` reused or mirrored).
- [x] The captions are Jake's copy, in `site/store/preview/captions.txt`, one per scene, so the
      words change without touching Swift and the marker rule applies to a text file.
- [ ] After the next approval the preview plays on the product page. Manual check, Jake.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
**The storyboard is a value.** `StorePreview.Scene` is (state, countdown, meters, caption,
seconds). `StorePreview.storyboard` is the list; at 30 fps it expands to frames. A test sums the
seconds and checks the bounds Apple sets. Captions come from `captions.txt`, matched by position.

**Frames come from the view.** Per scene the popover is put into its state with the hooks 0057
added (`setStateForScreenshot`, `setMetersForScreenshot`, `refreshForScreenshot`) and snapshotted
with `cacheDisplay`; meters get a new value each frame along a smooth curve, so the clip shows
them moving. Each frame composes the snapshot onto a 1920 by 1080 canvas the way
`StoreScreenshots.compose` does onto 2880 by 1800: the same gradient, the popover at a whole scale
that fits, the shadow, the caption in the system font along the bottom. The canvas colours and
scale rule move to a shared place so the pictures and the clip can't drift apart.

**The writer is the time-lapse's.** `TimeLapseRenderer.openWriter` already sets up an
`AVAssetWriter` for H.264 `.mov` at a given canvas; the preview uses the same code at 30 fps. The
output name is fixed (`oncue-preview-1920x1080.mov`) so the store script finds it by name.

**The store script.** `--preview` mirrors `--screenshots`. `sync_previews` mirrors
`sync_screenshots`: find or create the `appPreviewSets` entry of type `DESKTOP` on the version's
localization, list `appPreviews`, reconcile by file name and checksum, reserve, upload in parts,
commit with the checksum and a `previewFrameTimeCode`, then poll `assetDeliveryState` until
`COMPLETE` or `FAILED`. The API names here are from Apple's documentation as I remember it and
are unverified until the first dry run against the real version. Processing can take minutes;
the wait sits before the review submission, where `wait_for_build` already sits.

**Determinism.** The committed movie is the source of truth, as the PNGs are: the script compares
the file in the repo to the store's checksum, so a re-render only costs an upload when the clip
changed. Whether two renders of the same build are byte-identical is not relied on.

**Debug only.** `StorePreview.swift` sits beside `StoreScreenshots.swift` under `#if DEBUG`.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [x] The dry run against the real 4.22 version prints a plan, which confirms the API names
- [ ] The movie plays in QuickTime at the right size and length (Jake)

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes it himself. In a spec, describe what the copy must convey.

Copy to convey, one caption per scene: that you arm it, that it counts down so you can stop it,
that it watches motion and sound at thresholds you set, that it records while something happens,
and that afterwards it can tell you what happened while you were out.

## Tasks
- [x] `StorePreview.Scene` and `storyboard`, with the test on duration and coverage
- [x] Shared canvas (gradient, scale rule, shadow) between the pictures and the clip
- [x] Frame rendering and the H.264 writer at 30 fps; `-renderStorePreview` in `AppDelegate`
- [x] `captions.txt` under markers; the render reads it
- [x] `scripts/store --preview`; the self-test reading the movie back
- [x] `sync_previews` with reconciliation, upload, poster frame and the processing wait; the dry run
- [x] CLAUDE.md: the preview under `site/store/`
- [ ] Changelog line for the release it rides with, if any; the listing changes on its own

## Verification
- Rendered on this Mac, 2026-11-09: 1920 by 1080, 24.0 s, H.264, no audio, 7.2 MB; five frames
  pulled out with AVAssetImageGenerator show unarmed, "Arming… 2", armed with the meters up,
  recording with the meters red and yellow, and the stretch line at the end. The dry run against
  the live 4.22 localization reached its preview sets (none yet) and planned one upload.
- Two faults in the 0057 render found on the way and fixed: the "unarmed" picture had shipped
  saying "Armed on schedule", because a Debug build arms without a countdown and any defaults
  write re-read the schedule the overrides enable (`frozenForScreenshot`); and a pending update
  line from the user's own defaults showed in every picture (`pendingKey` overridden to empty).
  The seven pictures are re-rendered.
- Captions signed by Jake 2026-11-09 and the clip re-rendered with them; `scripts/check` green,
  447 tests.
- Not yet seen: the clip in QuickTime (Jake), and on the product page after the next approval.

## Open questions
1. **How long, and how many scenes? Resolved (Jake, 2026-11-09): about 24 seconds, six scenes.**
   A caption takes two seconds to read and the thing under it two more to register, so three to
   five seconds a scene; the countdown has to show enough to be visibly a count; and previews
   autoplay in search results where the first seconds are all most viewers give, so the arm and
   the meters come first and the stretch line last. Fifteen seconds would lose the recording and
   the stretch line, the two things that make it a camera rather than a meter.
2. **Where the preview is checked before it ships. Resolved (Jake, 2026-11-09): it rides with the
   next version; no version is cut to carry it.** Apple's processing is the real check and the
   script waits on it and fails loudly; the file's size, length and content are checkable here in
   QuickTime and by the self-test; what can't be seen before approval is taste, which a version
   of its own wouldn't help with. A bad clip would stay up until the next editable version,
   which is the risk accepted.
3. **Does the Settings window appear? Resolved (Jake, 2026-11-09): no, the popover only.** One
   window is one story in 24 seconds; the sixth picture already shows Settings at 4x one swipe
   away; and the popover is what owning OnCue is like most days. If the pictures ever drop
   Settings, this comes back.
