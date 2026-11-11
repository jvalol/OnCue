---
title: A time-lapse of what happened while armed
status: shipped
created: 2026-09-30
commits: c13b758 (approval), f765c05 (implementation), b2c1dd4 (built state, manual checks), 14ac4ad (the menu titles name the stretch), 0a9f952 and 51a45bf (released in 4.17)
---

## Problem
0054 gets you to the story: Finder with the stretch's files selected, stills first, and you step
through them. That's a contact sheet, and it answers "what were the events?". It doesn't answer
"what happened?" for a stretch with twenty recordings: opening twenty movies is still twenty
opens, and the still of each shows one moment out of thirty seconds. A time-lapse of the stretch,
one short movie with a frame every couple of seconds from every recording, in order, with the
time in the corner, is the thing to watch once and know. It's also the one file to send.

## Non-goals
- Not automatic. It's made when asked for, from the popover, not after every disarm. A stretch
  with nothing in it has nothing to make.
- No editing, no settings, no export dialog. One shape of movie, one place it goes.
- No sharing sheet. Finder has one.
- Not from the whole folder or a date range. It's the stretch 0054 remembers, and only that; a
  range picker is a later spec if the stretch turns out to be the wrong unit.
- No Shortcuts action yet. If it earns one, that's a line in 0050's file.

## Behaviour (acceptance criteria)
- [x] "Make a Time-lapse" in the popover menu, under Show What Happened, is enabled on the same
      condition: a remembered stretch with at least one event. Unit test on the validation.
- [x] Choosing it writes one H.264 movie to the recordings folder, named for the stretch, and
      reveals it in Finder when it's done. Manual check.
- [x] The movie holds, in time order, a frame every two seconds of each recording in the stretch,
      with each recording's still as its first frame, each frame held for a quarter of a second.
      Unit test on the plan (which frames, from which files, at which times) as a pure function;
      unit test that the writer produces a movie whose duration is the plan's, from a folder of
      test images.
- [x] Each frame carries the time it was taken and, when the stretch has two cameras, the
      camera's name, drawn in a corner; with one camera only the time. Manual check; the drawing is a pure function of the label, tested for not
      throwing on a frame of any size.
- [x] Frames of different sizes (two cameras at different resolutions) are letterboxed into the
      first frame's size, never stretched. Unit test on the placement rule.
- [x] The time-lapse's name is not one the rolling window (0029), the trigger-cost line (0033) or
      the stretch (0054) recognise as a recording: it's never deleted by the limit and never
      counted as an event. Unit test on `recordingDate(fileName:)` returning nil for it.
- [x] Making one doesn't stop OnCue watching: it runs off the main and capture queues, and arming
      or a trigger during it is unaffected. Manual check while armed.
- [x] A recording that can't be read (missing, unreadable) is skipped and the rest are used; if
      nothing can be read, nothing is written and the popover's line says so. Unit test on the
      plan with a missing file; manual check for the notice.
- [x] Making a second one for the same stretch replaces the first. Unit test on the name.
- [x] Every string is under the marker with German; `LocalizationTests` green. Unit test.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- **`TimeLapse`**, new, in `Managers/Helpers`, in both targets. `plan(events:, step:, hold:)`
  turns 0054's events into a list of frames: for each movie in each event, its still (if there
  is one) then a sample every `step` seconds of the movie's duration, each with the wall-clock
  time it represents (the file's timestamp plus the offset) and the camera name from the file
  name. Pure, tested. `outputName(for stretch:)` is "What happened 2026-09-26 07.09 to
  07.11.mov": starts with a word, so `recordingDate` says it isn't OnCue's, and the window and
  the counters leave it alone.
- **Frames from movies.** `AVAssetImageGenerator` with `requestedTimeToleranceAfter` of a
  second, which lands on keyframes (one a second, 0013) rather than decoding to the exact
  sample, so a thirty-second recording costs a dozen keyframe decodes. Stills are read with
  ImageIO. Each frame is drawn into a `CGContext` of the output size, letterboxed, with the
  label in the corner, then handed to an `AVAssetWriter` with a pixel buffer adaptor: H.264,
  the first frame's size, four frames a second (a quarter-second hold). All of it on a utility
  queue; the menu item is disabled while one is being made.
- **Output.** The recordings folder, so it sits with what it was made from and is where Show
  Recordings looks. Revealed in Finder when finished. Replacing an existing one for the same
  stretch is a `moveItem` over it.
- **The popover.** Nothing new to show while it's being made beyond the disabled menu item; a
  stretch of twenty recordings is a few seconds of work. If nothing could be read, the 0054
  line says so until the next open.
- **Rejected:** the stills alone (a slideshow, one frame per event, which 0054's Finder walk
  already is); every frame of every recording at speed (a real time-lapse decode of every
  sample, minutes of work for an hour of footage, for a result that's mostly the same frame);
  a subfolder for time-lapses (a second place to look, for a file people make on purpose);
  side by side for two cameras (kept for a later version, see open question 4).

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [x] A twenty-recording stretch on this Mac renders in under ten seconds (manual, timed)

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

## Tasks
- [x] `TimeLapse.plan`, `outputName`, the letterbox rule and the label, with tests
- [x] The renderer: frames from stills and movies, drawn and written, on a utility queue
- [x] "Make a Time-lapse" in the popover menu, validated, disabled while making, revealing the
      result; the 0054 line for the nothing-readable case
- [x] Catalog entries with German
- [x] Help page paragraph (marked, in `site/help`); the changelog entry comes with the release

## Verification
- **Built (2026-09-30):** `TimeLapse` (`Managers/Helpers`, both targets, no AppKit): `plan` from
  0054's events and a table of movie durations, still first then a sample every two seconds,
  interleaved across cameras by the moment shown with a fixed tie-break; `cameraName` from the
  file name (first device, 0024's suffix stripped); `outputName` ("What happened 2026-09-26
  07.09 to 07.11.mov", both days when it crosses midnight), which `recordingDate` refuses;
  `letterbox`, `label` (time, plus the camera with two), and `draw` with Core Text on a dark
  strip. `TimeLapseRenderer.render` loads durations with `AVURLAsset.load(.duration)` (a movie
  that won't load contributes nothing), samples with `AVAssetImageGenerator` at a keyframe
  tolerance of a second, draws each frame into a pixel buffer from the writer's pool and writes
  H.264 at four frames a second, to a hidden scratch name moved over any previous time-lapse
  for the stretch, 0o600. Nothing readable is a failure that writes nothing.
  `RecordingManager` carries `isMakingTimeLapse` and `timeLapseFailed`; the menu item is off
  while making and needs a stretch with files; the 0054 line says nothing could be read until
  the popover closes. Fourteen tests: camera names, the output name and its midnight form and
  that the window doesn't own it, the plan's order and sampling, a movie without a duration, two
  cameras interleaved, a foreign file left out, letterboxing three ways, the label with one and
  two cameras, drawing at three sizes, stills rendering to a quarter second each at the still's
  size, a rendered movie re-sampled every two seconds, nothing readable writing nothing, and a
  second run replacing the first. Clean build, 417 tests, no warnings. The ten-second gate for
  a twenty-recording stretch is a manual timing on this Mac.
- **Checked on this Mac (Jake, 2026-09-30 14:10):** the time-lapse from a real stretch, revealed
  in Finder, stills first then the samples with the time in the corner; two cameras interleaved
  and named; a second run replacing the first; a trigger recording while one was being made;
  the twenty-recording timing under the gate. Copy read; markers struck. Xcode's sync had
  re-extracted the two strings without their markers during the checks, so the duplicate
  entries were merged onto the extracted keys with their German. `scripts/check` green.

## Open questions
1. Resolved (Jake, 2026-09-30): a sample every two seconds of each recording, with the
   recording's still as its first frame. Stills alone are the slideshow Finder already gives;
   keyframe sampling is a dozen decodes per thirty-second recording.
2. Resolved (Jake, 2026-09-30): four frames a second, a quarter-second hold, fixed. Eight times
   speed, a thirty-second event in four seconds; slower is a slideshow, faster loses the label.
   A pace that adapts to the stretch was rejected: two time-lapses would play at different
   speeds.
3. Resolved (Jake, 2026-09-30): the recordings folder, under a name that starts with a word so
   the window, the cost line and the stretch never see it as a recording. Time-lapses
   accumulate; they're made on purpose and named for what they are, so that's the user's
   tidy-up. The Desktop was rejected as a surprise from an app that has only ever written to
   one folder.
4. Resolved (Jake, 2026-09-30): interleaved in time order with the camera's name on each frame
   when the stretch has two. Side by side, both cameras in one frame at half width, is the
   option Jake likes for a later version once two-camera users ask: it needs the two
   recordings' timelines aligned frame by frame, which the first version doesn't take on.

## Closure
Shipped in 4.17 (2026-09-30), direct download and the tap (cask `b469900`, `scripts/check-tap`
green), build 913 uploaded to App Store Connect by the release run; the store version follows
once 4.16 clears review. Found on the first look after shipping 0054's menu items: nothing named
the period once OnCue was armed again, so both titles now carry the stretch's span.
