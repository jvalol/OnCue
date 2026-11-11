---
title: The App Store listing follows each release from the repo
status: shipped
created: 2026-10-02
commits: 18414ab (approval), a23176b (implementation), 25951e4 (built state, manual checks), then the fixes from the first real run and the closure
---

## Problem
A release ends with the zip on the site, the cask on the tap and a build on App Store Connect,
and then a person opens a browser: creates the version, picks the build, pastes What's New from
the changelog, pastes the same review note as last time, submits. Five clicks and a paste, three
times a week lately, with two judgements on top: whether a newer build has made this version not
worth submitting, and which changelog entries the store's users haven't seen. Twice now a version
was skipped and the entries blended by hand. The listing's description and screenshots live only
in the browser, so they drift from the app with nothing to say so; the screenshots are four
features behind. Everything here except taking a screenshot is a call the App Store Connect API
answers, with the key the release script already holds.

## Non-goals
- No change to the direct release: the zip, the notarization, the cask and the two pushes stay as
  they are. This is the store half, after the upload.
- No screenshots taken of the screen. OnCue draws its own: a Debug launch argument renders each
  state to a PNG with made-up meter levels, so no camera, no Screen Recording permission, and
  the same picture every time.
- No store localization beyond English. The German listing is still its own later step (0043).
- No pricing, no in-app purchase, no availability changes. Those are set once, by hand.

## Behaviour (acceptance criteria)
- [x] `scripts/store <version>` finds the build whose `CFBundleVersion` matches the zip the site
      serves for that version, waits for Apple to finish processing it, and refuses with a clear
      line if no such build was uploaded. Manual check on a real release.
- [x] It creates the App Store version for that version string if none exists, or reuses one
      still being prepared, and attaches the build. It refuses, naming the version, while another
      version is waiting for or in review: one slot. Unit test on the decision from the API's
      version list; manual check.
- [x] What's New is every changelog entry newer than the version the store is selling, oldest
      first, each without its disclosure paragraph, joined by a blank line. Unit test on the
      extraction and the blend from the changelog HTML.
- [x] The review note is the one text, held in the script: the Movies entitlement explained
      through Record a Test, and the Focus Filter performing only while OnCue runs. Unit test
      that it's sent.
- [x] The description, keywords and promotional text come from `site/store/`, one text file
      each, and are sent only when they differ from what the store holds. Unit test on the
      diff; manual check that an unchanged listing sends nothing.
- [x] A Debug build launched with `-renderStoreScreenshots <folder>` writes a PNG at 2x of each
      state worth a picture and quits: the popover unarmed with the stretch line, arming with
      the lid warning, armed on a schedule, armed with two cameras (Jake asked for it on the
      first look, 2026-10-02), and recording; Settings with the second camera chosen when the
      Mac has one; and the menu bar icon strip. The levels and the state are set, not captured. Manual check that
      the folder fills and the pictures match the app.
- [x] `scripts/store --screenshots` renders through that build, composites each PNG onto the
      store's canvas, and writes `site/store/screenshots/`. Unit test on the compositing
      placement; manual check on the result.
- [x] Screenshots in `site/store/screenshots/` are uploaded in file-name order when a file is
      new or its checksum differs from the store's, and removed from the store when the file is
      gone. Unit test on the reconciliation from the API's set; manual check on upload.
- [x] The release type is automatic on approval. Unit test on the payload.
- [x] `--dry-run` prints every call it would make, with the texts, and sends nothing. Manual
      check on the first two releases.
- [x] A check refuses a What's New or description that puts "Mac" in a name-like position
      (5.2.5) before anything is sent; body copy may say Mac. Unit test on the rule.
- [x] `scripts/check` runs the script's self-tests. Unit test that they're green.
- [x] `scripts/release` with `APP_STORE=submit` runs the upload and then `scripts/store` for the
      version it built; `APP_STORE=upload` stays as it is. Manual check.
- [x] No `[COPY - Jake]` marker remains in shipped copy. The description and promotional text
      in `site/store/` are copy and arrive marked.

## Design
- **`scripts/store`**, a Python 3 script with no dependencies beyond the system's: the API
  token is an ES256 JWT signed with `openssl` from `ASC_KEY`, `ASC_KEY_ID` and `ASC_ISSUER`, the
  same three the release script reads. Pure parts (changelog extraction, the blend, the slot
  decision, the screenshot reconciliation, the "Mac" rule) are functions with `unittest` cases
  in the same file, run by `scripts/store --self-test`, which `scripts/check` calls.
- **The API calls, in order.** `builds` filtered by app and version until `processingState` is
  `VALID`; `appStoreVersions` for the app to find the live version, any version in review, and
  one for this string; create or reuse; `PATCH` the version with the build and
  `releaseType: AFTER_APPROVAL`; `appStoreVersionLocalizations` for `whatsNew`, `description`,
  `keywords`, `promotionalText`; `appStoreReviewDetails` for the note; `appScreenshotSets` and
  `appScreenshots` (reserve, upload the parts, commit with the checksum); finally
  `appStoreVersionSubmissions`.
- **The changelog as the source.** The entry for a version is the `<h3>` block in
  `site/changelog/index.html`, which the release script already checks exists; its paragraphs
  minus the one that starts "I asked AI" become What's New. The blend walks versions newer than
  the store's live `versionString`, so a skipped version's entry is carried without anyone
  remembering it was skipped.
- **The listing files.** `site/store/description.txt`, `keywords.txt`, `promotional-text.txt`,
  seeded from what the store holds today so the first run sends nothing. `screenshots/` holds
  PNGs at the store's Mac sizes, named to sort in the order they should appear, written by the
  render step rather than by hand.
- **Rendering.** In the app, Debug only, beside 0035's failure flags: `-renderStoreScreenshots`
  builds the popover and Settings view controllers off screen, puts each into a state through
  the same calls the tests use (a `RecordingManager` of its own with a fixed clock, meter levels
  set directly, a remembered stretch written to its defaults), asks each view for its bitmap at
  2x, writes the PNGs, and exits. The icon strip is the five asset images in a row. The store
  script runs the Debug build from `DerivedData` with that argument, then composites each PNG
  centred on a dark canvas at the store's largest Mac size.
- **In the release.** `APP_STORE=submit` is `upload` plus a call to `scripts/store "$version"`
  at the end; the store script's own waiting covers Apple's processing. Nothing in the direct
  release waits on it: a store failure after a direct release is a line to read and a script to
  re-run, as 0036 arranged.
- **Rejected:** fastlane (a Ruby toolchain for six API calls); storing the listing texts in
  App Store Connect alone (the drift this spec exists to end); submitting from `scripts/release`
  without the separate script (a store problem would then look like a release problem).

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green, the store
      self-tests green)
- [x] `scripts/store 4.19 --dry-run` on the first release after this ships, read before the real
      run

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

## Tasks
- [x] `scripts/store`: token, calls, the pure parts and their self-tests
- [x] The render mode in the app, Debug only, and `scripts/store --screenshots`
- [x] `site/store/` seeded from the live listing; screenshots rendered, not today's pictures
- [x] `scripts/check` runs the self-tests; `scripts/release` learns `APP_STORE=submit`
- [x] CLAUDE.md: the store step and where the listing lives

## Verification
- **Built (2026-10-02):** `scripts/store`, Python 3 with nothing beyond macOS: the token signed
  with openssl; `changelog_entries` (an HTML parser over the changelog's `<h3>` blocks, dropping
  the date and the disclosure paragraphs), `whats_new` (every entry newer than the live version
  up to this one, oldest first, 4000-character limit), `slot_decision` (selling, blocked by the
  version named, reuse, create), `names_the_mac` ("for Mac", "on the Mac", "Mac app"),
  `screenshot_plan` (upload what's new or changed by checksum, delete what's gone or replaced,
  keep the file-name order), `listing_changes`; eight self-tests including one over the real
  changelog, run by `scripts/check`. The submit flow: build from the zip's `CFBundleVersion`,
  wait on `builds` and `buildUploads`, create or patch the version with the build and
  `AFTER_APPROVAL`, the `en-US` localization's What's New and changed listing fields, the review
  note, the screenshot set, then `reviewSubmissions` and its item. `--dry-run` prints every
  non-GET call. `--pull-listing` wrote `site/store/` from the live 4.18: description, keywords,
  an empty promotional text, and the review note, which lives there as a file rather than in
  the script (a text Jake can edit beats one he can't). `scripts/store 4.18 --dry-run` read the
  zip (build 915), found 4.18 on sale and stopped, as it should. `APP_STORE=submit` in
  `scripts/release` is upload then `scripts/store "$version"`.
- **The pictures:** `StoreScreenshots` (Debug only, app target): the overrides go into the
  volatile argument domain before anything reads defaults; the popover is hosted in a borderless
  dark window and drawn in four states through three hooks (`setStateForScreenshot`, which also
  marks the devices available because arming clears the fresh-start flag and that defaults
  write would otherwise auto-disarm it, `overrideForScreenshot(lidWouldStopWatching:)`,
  `setMetersForScreenshot`), with a folder of twelve made-up recordings and stills for the
  lines, and a fifth picture with the second camera's column (its name from a second camera on
  the Mac, else a made-up one); Settings is drawn from its window's frame view, title bar
  included, with the second camera chosen through the same volatile overrides; the icon strip
  is the five states named. Composition happens in the app rather than in the script, since the
  app has CoreGraphics and Python has nothing: 2x on a 2880 by 1800 dark canvas, the popover
  clipped to rounded corners with an arrow. `scripts/store --screenshots` builds Debug into its
  own derived data, runs the binary, and copies the six PNGs into `site/store/screenshots/`.
  Rendering found a real bug: the cost line counted the stills beside recordings as recordings,
  fourteen for seven, since 0053 made them OnCue's own by name; `TriggerCost.summary` now counts
  movies only, with a test. Clean build, 426 tests, no warnings.
- **Checked on this Mac (Jake, 2026-10-02 08:20):** the seven pictures read; a two-camera
  picture was asked for and added. The listing texts pulled from the store read. Icon labels
  struck. `scripts/check` green with the self-tests in it.
- **The first real run (2026-10-02, 4.19 on build 916):** the dry run first tripped over its
  own pretend id, asking Apple for a version called "dry-run"; a dry run now diffs against the
  live version, which is what a new version starts as a copy of, while a real run reads the
  version it writes (the first draft would have written the pictures into the live version's
  set). Read and approved by Jake. The real run created 4.19, set What's New and the note, and
  replaced the three old pictures with the seven new ones, then was refused at the submission:
  the build had no export-compliance answer, the "Missing Compliance" click. The script now
  answers `usesNonExemptEncryption: false` on the build before submitting, Info.plist carries
  `ITSAppUsesNonExemptEncryption` so uploads arrive answered, and a review submission left open
  by a failed run is reused rather than opened again. The second run submitted: the API lists
  4.19 WAITING_FOR_REVIEW. `APP_STORE=submit` in the release script wasn't used for this one,
  since the spec asked for the dry run to be read first; it's the mode from 4.20 on.

## Open questions
1. Resolved (Jake, 2026-10-02): automatic on approval. The store has followed the direct
   channels since the lockstep was dropped, and a manual release is the browser visit this
   spec removes.
2. Resolved (Jake, 2026-10-02): in scope, and the pictures come from the app. A Debug launch
   argument renders each state to a PNG with set levels and state; the store script composites
   and uploads them. Nobody takes a screenshot, and the pictures regenerate with every release
   so they can't drift. Costs a day's work in the app for the render mode.
3. Resolved (Jake, 2026-10-02): the self-tests run in `scripts/check`. The failure they catch,
   the changelog parser breaking, is a release failure, and the gate is where releases are
   proven. Python 3 comes with Xcode's Mac.

## Closure
Shipped with 4.19 (2026-10-02): the first store submission made by `scripts/store`, after a
dry run read first. The direct release went out the same morning (master `dfe2411`, cask
`3c40754`, check-tap green). From 4.20 the release runs with `APP_STORE=submit`.
