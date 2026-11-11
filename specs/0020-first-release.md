---
title: Ship a downloadable release
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-19
commits: f0f5d2a, 67ba19b (spec), 61b8ecb, bb62dbf, 1fd9757 (implementation)
---

## Problem
There's no download, so using OnCue means having Xcode and building it. Everything else is in
place: the app does what the page describes, and the page is live.

## Non-goals
- Automatic updates (Sparkle or similar): worth its own spec once there's something to update from.
- The Mac App Store, unless it turns out to be the better route (see Open questions).
- Paid licensing; the 2017 purchase flow isn't coming back.

## Behaviour (acceptance criteria)
- [x] A released build opens on a Mac that has never seen OnCue, with no Gatekeeper warning beyond
      the usual first-run prompt. Manual check on a second Mac, or a fresh user account.
- [x] Camera and microphone prompts appear and work in the released build, and recordings land where
      Settings says. Manual check.
- [x] The release is downloadable from the site, with its version and date shown. Manual check.
- [x] A script builds, signs, notarizes, and packages the app in one go, and refuses to package an
      unsigned or un-notarized build. Manual check by running it.
- [x] The version is set in one place, and the About window, the app, and the download all agree.
      Manual check.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- `scripts/release`: archive with `xcodebuild archive`, export with a Developer ID profile, submit
  with `notarytool`, staple with `stapler`, and zip the result. It stops on anything unsigned,
  un-notarized, or un-stapled.
- Version: `MARKETING_VERSION` in the project becomes 4.0 and is the single source; the script reads
  it for the file name and the release notes.
- Hosting: the zip is committed under `site/downloads/` and served by Netlify alongside the pages;
  the site's "Getting it" section becomes a download button with the version and date.
- The site isn't templated, so version and date are edited by hand there. `scripts/release`
  refuses to build unless `site/index.html` already links to the zip it's about to produce and
  names that version in its release line. That's what keeps the page and the build from
  disagreeing.
- Release notes: what shipped in specs 0002 to 0019, written for people rather than as a spec list.

## Gates
- [x] `scripts/check` passes
- [x] The released build runs on a Mac that hasn't had OnCue before

## Tasks
- [x] Confirm the signing and notarization setup (Open questions)
- [x] `MARKETING_VERSION` 4.0 and the signing team, both targets
- [x] `scripts/release`
- [x] Download on the site, with version and date
- [x] Release notes
- [x] `xcrun notarytool store-credentials oncue-notary`
- [x] Rehearse `scripts/release` end to end
- [x] Run `scripts/release` for real, and commit the zip
- [x] Manual checks, Verification filled in

## Verification

**Rehearsal, 2026-09-19.** `scripts/release` ran end to end and produced a real notarized 4.0,
signed as `EggDevil` since the renamed certificate doesn't exist yet. The zip was deleted
afterwards and `CFBundleVersion` put back, so nothing from the rehearsal ships.

Checked on the produced app, independently of the script:

- `flags=0x10000(runtime)`, so the hardened runtime is on
- `Authority=Developer ID Application: EggDevil (A2MVZ4JVLC)`, chaining to Apple Root CA
- `codesign --verify --deep --strict` passes
- `xcrun stapler validate` passes, so the notarization ticket is in the app and works offline
- `spctl -a -vvv -t exec`: `accepted`, `source=Notarized Developer ID`
- `CFBundleShortVersionString` is 4.0, from `MARKETING_VERSION`
- `lipo -archs`: `x86_64 arm64`

Refusals exercised: a dirty working tree, a site that links to a different version's zip, a site
whose release line names a different version, and a destination zip that already exists. All four
stop before anything is built.

Not yet exercised: the checks that run after the build, on a signature that's wrong or a
notarization that comes back rejected. Those only fire on a genuinely broken build.

The version guard was wrong on its first run and let a page naming 9.9 through: `grep "4.0"` is a
pattern, and it matched the `400,700` in the stylesheet link. It now matches fixed strings, and
checks the download link as well as the version.

**Release, 2026-09-19.** 4.0 went out and the site is live at oncue-web.netlify.app. Downloaded
from the public URL and checked: `sha256 5ecda44e...ba16`, matching what was built, the staple
validates offline, and `spctl` returns `accepted`, `source=Notarized Developer ID`.

Jake's manual checks: the downloaded zip installed to `/Applications`, Finder reported Version
4.0, and the app ran with live sound and motion meters from both the C920 and the built-in camera,
so camera and microphone both work in the released build. No Gatekeeper block.

What that doesn't cover, since the boxes are ticked on it: the install was on this Mac, which has
run development builds, not a machine that had never seen OnCue. A recording wasn't made from the
released build to confirm where files land, and the About window wasn't opened, though the app,
Finder, and the site all report 4.0.

**Edge Light.** Running the released build lit the screen edges. That's Edge Light, a macOS 26.2
camera effect that illuminates your face, confirmed with `AVCaptureDevice.isEdgeLightEnabled` and
`isEdgeLightActive` both true. It is not OnCue's doing and OnCue cannot turn it off: the
properties are read-only, there's no control mode as there is for Center Stage, no Info.plist
opt-out as there is for Studio Light, and all seven built-in camera formats support it. External
cameras don't, so a C920-only setup never triggers it. Jake found the switch in FaceTime's own
menus. Worth knowing for later: it lights the room OnCue is watching, and it follows camera use
rather than arming, so it's on whenever OnCue is open.

## Open questions
1. Resolved (Jake, 2026-09-19): there is a paid Apple Developer Program membership, so the release
   is signed with a Developer ID certificate and notarized. The certificate now exists, on team
   `A2MVZ4JVLC`; the project moved to that team, since the other one it was building under
   (`ZUK3TME68V`) has no Developer ID certificate and can't notarize.
2. Resolved (Jake, 2026-09-19): the repo stays private. "I can open it down the road if there's a
   reason but right now there's not." The five links to github.com/jvalol/OnCue are off the site,
   and the download lives on the site itself rather than on GitHub Releases.
3. Resolved (Jake, 2026-09-19): the release is 4.0.
4. Resolved (Jake, 2026-09-19): 4.0 ships signed as `EggDevil`, a dissolved LLC, rather than
   waiting on a rename Jake has tried before and found to be a dead end. There are no users yet,
   and re-signing later costs nothing that matters: the app's designated requirement keys on the
   team ID, which stays `A2MVZ4JVLC` whatever the certificate is called, so a later change doesn't
   reset camera and microphone permissions or invalidate anything the app has stored.
