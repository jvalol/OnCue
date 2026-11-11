---
title: Say what changed after an update, with the changelog
status: shipped
created: 2026-10-02
commits: 979a550 (approval), 6ed6243 (implementation), a86fb15 (built state, manual checks), d336c1d and d7e3ccc (released in 4.20)
---

## Problem
About 1,200 store installs took an update in the last quarter (App Store Connect, 2 October
2026). Most of them had been on 3.0.3 for years, and the update put nineteen releases of change
in front of them with nothing said: the fresh-start notice (0037) doesn't fire, since their
container isn't empty, and OnCue has never stored which version last ran, so it can't tell an
update from a launch. The changelog on the site explains every change, with the AI disclosure
on each entry, and nobody coming from the store knows it exists. The same holds for a direct
user who updates through brew without reading the feed. One line after an update, pointing at
the changelog, is the difference between "this got weird" and "this is what changed".

## Non-goals
- No changelog inside the app. The site's page is the changelog; the app points at it, and the
  browser does the fetching, so OnCue still has no network permission.
- No notification. An update is noticed when the popover is next opened, which is when the
  person is looking.
- No per-version messages, no onboarding, no tour. One line with a link.
- No change to the fresh-start notice; where both apply (a direct user's first 4.x launch after
  the bundle ID change), the fresh start wins, since it's the one with a consequence.

## Behaviour (acceptance criteria)
- [x] OnCue remembers the version that last ran, written at every launch. Unit test.
- [x] When the version that last ran differs from the one running, the popover's notice line
      says OnCue was updated to this version and that the changelog says what changed. It's a
      link: clicking opens the site's changelog in the browser, at the entry for this version.
      Unit test on the rule and the URL; manual check.
- [x] A launch with no remembered version into a container that isn't fresh is an update from
      before this release, which for the store means 3.0.3: the line says OnCue was updated from
      an older version, since the number isn't known, with the same link. Unit test on the rule.
- [x] The line ranks as information, not a risk: below everything that happened and below the
      fresh start, above the lid warning and the schedule warning. Unit test on the ranking.
- [x] The line stays until it's clicked, or until the next update replaces it. Opening the
      popover alone doesn't clear it; a line nobody has read is still owed. Unit test on
      persistence; manual check across a relaunch.
- [x] The changelog page has an anchor per version, so the link lands on the right entry.
      Checked by the store script's self-test, which already parses the page.
- [x] German for the strings (0043); `LocalizationTests` green. Unit test.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- **`UpdateNotice`**, new, in `Managers/Helpers`, AppKit-free, both targets. Keys
  `lastRunVersion` and `updateNoticePendingFor` (the version the line is about, or nothing).
  `check(running:lastRun:fresh:)` is the pure rule: fresh → nothing (0037 speaks); no last
  run → `.fromOlder`; different → `.to(version)`; same → nothing. `note(at launch)` applies it
  and writes both keys; `clear()` on click. `url(for version:)` is the changelog page with
  `#v4-19`.
- **The popover.** A new `PopoverNotice` case, `updated(from: Update)`, ranked after
  `freshStart` and before `scheduleCannotSurviveRestart`. The notice label is already a text
  field; while this notice shows, a click gesture opens the URL and clears the notice, the way
  the 0054 line became a button. Colour: the link colour, so it reads as one.
- **The changelog anchors.** Each `<h3>` in `site/changelog/index.html` gets `id="v4-19"` form
  ids; the release preparation adds the next one, and the store script's changelog parser
  checks every heading has one.
- **Launch order.** `AppDelegate` notes the update right after the defaults registration and
  the fresh-start check, before the popover exists, so the first open shows it.
- **Rejected:** a macOS notification at launch (nobody asked to be interrupted by a changelog);
  showing the entry's text in the popover (it's paragraphs, and the page has the disclosure
  the policy requires); a "What's New" window (a window for one line).

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

## Tasks
- [x] `UpdateNotice`: the rule, the keys, the URL, with tests
- [x] The notice case, its ranking and the click, in `SleepRisk` and the popover
- [x] Anchors on the changelog headings; the parser's check; the release preparation habit
- [x] Catalog entries with German
- [x] Help page sentence (marked, in `site/help`); the changelog entry comes with the release

## Verification
- **Built (2026-10-02):** `UpdateNotice` (`Managers/Helpers`, both targets, Foundation only):
  `check(running:lastRun:fresh:)` is the rule, `note(running:fresh:)` applies it at launch and
  remembers the version, `pending` reads the line owed ("older" or a version under one key),
  `clear()` pays it, `anchor(for:)` and `url(for:running:)` point at the changelog's heading.
  `PopoverNotice.updated(_:)` ranks after the fresh start and before the two risks. The
  popover's notice label is a `ClickableLabel` now (the storyboard's custom class; the class
  went internal), with a click gesture that opens the URL and clears the line; while the update
  line shows it's in the link colour with the pointing hand, otherwise the storyboard's orange.
  `AppDelegate` notes the update after the fresh-start check, with "fresh" captured before the
  flag is cleared, and not while drawing the store pictures, whose overrides also remember the
  running version so no line appears in them. Every changelog heading carries `id="v4-19"`
  form ids and the store script's parser now fails its self-test on a heading without one.
  Ten tests: the rule's four cases, the launch round trip (owed, kept across a same-version
  launch, replaced by the next update, cleared stays cleared), a fresh container remembering
  without owing, the anchor and both URLs, and the ranking against the risks, the fresh start
  and a failure. Clean build, 434 tests, no warnings.
- **Checked on this Mac (Jake, 2026-10-02 09:53):** the line on the first launch of the build,
  the click opening the changelog, the line surviving a relaunch and an arm, and gone after the
  click. Copy reworded by Jake ("See what changed"); markers struck. `scripts/check` green.

## Open questions
1. Resolved (Jake, 2026-10-02): the line stays until it's clicked or until the next update
   replaces it. The thing owed is a link, and a line that cleared on the first arm would miss
   the 3.0.3 users it exists for. Each update replaces the last line, so one lingers at most.
2. Resolved (Jake, 2026-10-02): on the first launch of the release that ships this, everyone
   gets the "from an older version" line once, direct users included, since nobody has a
   remembered version yet. True for all of them, exactly right for the 3.0.3 users, and the
   alternative is machinery for one release. The changelog entry says so in a sentence.
3. Resolved (Jake, 2026-10-02): the link lands on the running version's entry, by an id per
   heading that the store script's parser checks for. For a 3.0.3 user that's the top of the
   page, which is where nineteen releases of reading starts.

## Closure
Shipped in 4.20 (2026-10-02), direct download and the tap (cask `d4a9319`, `scripts/check-tap`
green). The first release run end to end with `APP_STORE=submit`: build 917 uploaded and
processed, and the store step stopped at the review slot 4.19 still held, as designed; a watcher
runs `scripts/store 4.20` when it clears.
