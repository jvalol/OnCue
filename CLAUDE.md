# OnCue

A macOS menu bar app that watches the camera and records to `~/Movies/OnCue` when it sees
motion. Arming counts down, then any motion over the trigger threshold starts a recording that
keeps going while motion continues. It's a small security camera, so reliability while unattended
beats features.

## Spec-driven development

Changes that add a capability, change behaviour a user relies on, or add UI start as a spec in
`specs/` that Jake approves (`status: draft` → `approved`) before any code. The line is
capability, not size. Bug fixes are a failing test plus the fix; mechanical work skips the spec.
See `specs/README.md`.

- `/spec-new <description>` drafts a spec and stops.
- `/spec-implement <number|slug>` builds an approved spec, keeping it current.
- `/spec-list` shows what's in flight.

Each acceptance criterion maps to a unit test, or to a named manual check when it needs a real
camera, the menu bar, or sleep behaviour.

## Working rules

- **Apply, don't commit.** Claude makes the change and runs `scripts/check`, then leaves the diff
  in the working tree. Jake commits, or tells Claude to. Scope every commit with
  `git commit -- <paths>` so his staged work is never swept in.
- **Spec files never share a commit with implementation.** Approval, box-ticking, and closure each
  commit on their own.
- **User-facing text is Jake's.** Anything a user sees (UI strings, storyboard labels, permission
  prompts in `Info.plist`, the About window, the README) is proposed with a `[COPY - Jake]` marker.
  Only Jake removes it. Marked copy stays uncommitted. `scripts/ship-check` fails while one
  remains. Specs, this file, `.claude/`, code comments, and commit messages are not copy.
  Neither are the changelog and its feed: Jake ships Claude's wording there as drafted, no marker,
  with the AI disclosure line as the entry's last paragraph (decided 2026-09-22).
  The site's pages, the store texts and the README are also signed: `.copy-files` names them,
  Jake signs with `~/.claude/voice/sign-copy`, which shows him each file and writes its hash to
  `.copy-signed`, and `scripts/ship-check` runs `check-voice` against that when it's installed.
  Signing is what clears a marker in those files; nobody strikes them on a say-so (2026-11-09).
- **Memory stays out of the repo.** Project memory lives in `.claude/memory`, which git ignores
  because this repo is public (the `~/.claude/projects/-Users-jake-Developer-oncue/memory` path is
  a symlink to it). It holds private notes: it is never committed, and nothing from it goes into a
  spec, a commit message or this file unless Jake says so.
- **This repo is public.** Every commit, message, spec and line of this file is public reading.
  Commits here use the GitHub no-reply address set in this checkout's own git config, not the
  global one. The history starts with one commit; everything before it is in a private archive,
  so a commit hash named in an older spec doesn't resolve here.
- **Push is Jake's.** Commits go straight to `master`; there's no CI.
- **A release isn't shipped until the tap is pushed too.** `scripts/release` rewrites the cask in
  `../homebrew-tap`, but that's a file on disk. brew reads the tap from GitHub, so until that repo
  is committed and pushed, `brew install` and `brew upgrade` still hand people the previous
  version while everything here looks finished. Two repos, two pushes, every version. Confirm with
  `scripts/check-tap`, which is the only thing that can see the difference.
  Jake authorized Claude to push the tap itself, on 2026-09-21, for this release and every one
  after. That is the one push Claude makes without being asked each time, and only as part of
  shipping a version that has already gone out here.
- `scripts/check-tap` clones the tap over git and fetches the zip over https, which is how brew
  gets each of them, and it prints the tap commit it read. It used to read the cask from
  `raw.githubusercontent.com`, which caches for five minutes: after the 4.6 push that reported the
  old version for three minutes while git already had the new one, which is a check crying wolf at
  the one moment anybody runs it.

## Commands

- `scripts/check` is the gate: copy markers, then a clean build and the unit tests, with
  signing off. It puts the build number back afterwards.
- `scripts/ship-check` checks for copy markers only.
- A changelog entry's heading carries `id="v4-20"` for 4.20: the app's update line links to it
  (spec 0058) and the store script's self-test fails on a heading without one.
- `scripts/site` serves `site/` at `http://localhost:8765` (or a port you pass), the way Netlify
  does. Check site changes through it, not by opening the HTML as a file: a page rendered without
  its stylesheets is exactly the condition under which layout bugs are invisible, and two were found
  only once the site was served. `.claude/launch.json` runs the same script for the browser pane.
- `scripts/release` archives, signs with Developer ID, notarizes, staples, and leaves the zip in
  `site/downloads` for Netlify to serve. It runs `scripts/check` first and stops at anything
  unsigned, un-notarized, or un-stapled. Jake runs it; its build number bump is real and stays.
  It also rewrites the Homebrew cask in the tap beside this repo, which `SKIP_TAP=1` turns off.
  `APP_STORE=upload` sends the same archive to App Store Connect at the end; without it the run
  stops after the direct release, and the zip it left refuses a second run. For that case
  `STORE_FROM_ARCHIVE=1 APP_STORE=upload scripts/release` re-exports the archive the run left
  (4.14, 2026-09-25). `APP_STORE=submit` is upload plus `scripts/store <version>`, which waits
  for Apple to process the build, creates or reuses the store version, sets What's New from every
  changelog entry the store's users haven't seen, syncs the listing texts and screenshots from
  `site/store/`, and submits for review (spec 0057). `scripts/store <version> --dry-run` prints
  every call and sends nothing; it refuses while another version holds the review slot.
- `site/store/` is the App Store listing: `subtitle.txt`, `description.txt`, `keywords.txt`,
  `promotional-text.txt`, `review-note.txt`, `screenshots/`, and `preview/` (the clip and its
  `captions.txt`, spec 0061; `scripts/store --preview` renders it the way `--screenshots` does). The subtitle lives on the app
  record rather than the version and locks once a version is waiting for review, so the script
  sets it on the in-flight record before submitting. The texts are Jake's copy. The
  pictures are drawn by the app: `scripts/store --screenshots` builds a Debug OnCue and runs it
  with `-renderStoreScreenshots <folder>`, which renders the popover in each state, Settings and
  the icon strip onto the store's canvas with set meter levels and a made-up stretch, then quits.
  It also cuts `site/images/card.png`, the picture a link to the site unfurls with, from the armed
  picture (`scripts/store --card` does that alone).
  `scripts/store --pull-listing` overwrites the texts with what the store holds. `scripts/check`
  runs the script's self-tests.
- Measuring the motion pass: a Debug build run with `ONCUE_MEASURE=<file the sandbox can write>`
  (something under `~/Movies/OnCue` works) appends the GPU time per frame every 300 frames to that
  file, and a histogram of how far past the cutoff the marked pixels are (`magnitude:` lines, 0040's
  grading question). Launch it with `open -n <app> --env ONCUE_MEASURE=... --args -armAtLogin YES` rather than
  from a shell, or the camera is refused: launched from a shell the camera grant is attributed to
  the terminal's host process. Process CPU comes from `ps`. Compare builds by running them turn
  about in the same room, sixty seconds each; the hour changes the numbers more than code does.
- Debug builds append a line to `~/Movies/OnCue/intents.log` each time a Shortcuts action or the
  Focus Filter performs (spec 0050). The unified log isn't readable from Claude's shell, so this is
  how a Focus delivery is checked. Shortcuts, Siri and Focus index the copy registered under
  `/Applications`; after replacing that copy, a Focus Filter already attached to a Focus has to
  be removed and re-added before it's delivered again.
- `scripts/soak` samples a running OnCue into a log every five minutes (memory, threads,
  descriptors, recordings, free space); `scripts/soak --cycles N` arms and disarms it through the
  popover's buttons for the sampler to watch. Baseline from 4.22 is in memory (`soak-baseline-4-22`).
  Launch the app with `--args -scheduledArmingEnabled NO` for a soak, or the schedule's window takes
  the arm and ends it (2026-11-10).
- `scripts/check-tap` asks GitHub and the site what they actually serve, and whether the published
  cask and the published zip agree. It needs the network, so it isn't part of `scripts/check`, and
  it's the only check that can see a cask written here and never pushed. Run it after pushing both
  repos: until then brew installs the previous version and nothing on this machine looks wrong.

## Quirks

- The Run Script build phase bumps `CFBundleVersion` in `OnCue/Info.plist` on every build, so
  any Xcode run leaves the file modified. The number only matters at release: `scripts/release`
  refuses to ship one that isn't above every zip in `site/downloads` and writes back the number it
  actually built. So a bump from any build is fine to commit with whatever else is going in, and
  never worth reverting. `scripts/check` undoes its own.
- `OnCue/Main.xcstrings`, the storyboard's String Catalog, is filled by hand and every entry is
  `extractionState: manual`. Xcode's IDE sync doesn't see the storyboard for that catalog: a build
  from Xcode marked all 28 visible entries stale and deleted the 134 hidden-menu ones outright
  (2026-09-23). Manual entries are left alone. A new storyboard string gets its `ObjectID.title`
  entry added by hand; `LocalizationTests` names any that's missing. The code and Info.plist
  catalogs sync fine. A code key added by hand uses plain `%@` and `%lld` specifiers, the way
  Xcode extracts them; a positional `%1$@` key gets marked stale and re-extracted plain the next
  time Xcode builds (2026-09-26). The German value may still use positional specifiers.
- Image lookup is case-sensitive: a storyboard or `NSImage(named:)` name must match the asset
  catalog entry exactly (`Preferences`, not `preferences`).
- Test sources compile the app's files directly into the test target, so tests don't
  `@testable import OnCue`.
- Signing uses team `DC3U4XZMM4`, Jake's individual developer account, since
  2026-09-22. The old team, `A2MVZ4JVLC`, is EggDevil, a dissolved LLC; its certificate is still
  in the keychain and `scripts/release` refuses it by team ID. Nothing ships from EggDevil again.
  Xcode 27 needs the Metal Toolchain component (`xcodebuild -downloadComponent MetalToolchain`)
  to build the shaders.

## Layout

- `OnCue/Managers/CaptureManager.swift`: capture session, device selection, motion scan, start and stop of recordings
- `OnCue/Managers/RecordingManager.swift`: arm/countdown/record state machine, keep-awake while armed
- `OnCue/Managers/Helpers/MotionDetector.swift`: motion level scale and threshold test
- `OnCue/Managers/FileOutputManager.swift`: recording file names and location
- `OnCue/Preview/MotionDetectMetalRenderer.swift` and `Shaders/MotionDetect.metal`: GPU frame diff
- `OnCue/Popover/`, `OnCue/Settings/`: menu bar popover, settings and About windows
- `OnCueTests/`: XCTest unit tests
