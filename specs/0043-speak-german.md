---
title: Speak German
status: shipped
created: 2026-09-23
commits: 645fa45 (approval), 8674dea (implementation), 6ad08f6 (built state, manual checks), 04142f0 and e00fa7e and 4c6c6b9 (released in 4.11)
---

## Problem
Every word OnCue shows is an English literal: about 131 titles in the storyboard, 44 strings in
code across nine files, and the two permission prompts in `Info.plist`. Nothing goes through
`NSLocalizedString` or a String Catalog, and the project declares only `en` and `Base`. A German
Mac gets English menus, an English popover, and English permission prompts from the system dialog.
German is the one other language Jake reads, so it's the one that can be added and checked, and it
is the test of whether the app can be localized at all: the first language finds every string that
was assembled from pieces or sized by hand.

## Non-goals
- Any language but German. Each further language ships unread by anyone here; that's its own
  decision, with its own rules for copy nobody can strike.
- Translating the site, the help pages, the changelog, or the App Store listing. The app first;
  those are separate surfaces and separate specs.
- Localized recording file names. Names stay `en_US_POSIX` so they sort and parse the same
  everywhere (spec 0017's parser depends on it).
- A language picker in Settings. The app follows the system language, as Mac apps do.
- Right-to-left, plural rules beyond German's, or locale-specific number input. German has two
  plural forms and the numbers in Settings are plain integers.

## Behaviour (acceptance criteria)
- [x] On a Mac set to German, everything the app shows is German: menu bar menu, popover, Settings,
      About, the preview window's hint and button, the schedule rows, notifications, and the camera
      and microphone permission prompts. Manual check with the system language set to German (or
      the app run with `-AppleLanguages '(de)'`).
- [x] On a Mac set to English, or any language that isn't German, nothing changes: every string is
      byte-identical to today's. Unit test on the English catalog entries against the strings the
      code produces; manual check that the popover and Settings look as before.
- [x] Counts read correctly in both languages at 1 and at many: recordings in the last day, oldest
      recordings deleted, recordings in a row not saved. Unit test on the formatted strings at
      counts 1, 2 and 5 in `en` and `de`.
- [x] The recording-failure notice is one sentence per case, not a clause joined to a count, so
      German word order is possible. Unit test on each case at count 1 and 3.
- [x] Times and weekdays in the schedule and the armed description come out in the system's own
      format and language. Already the case via `Calendar` and `DateFormatter`; unit test pinning
      `describe(end:now:calendar:)` with a `de_DE` calendar.
- [x] Nothing is clipped: every label that grows in German has room or wraps. Manual check of the
      Settings window, the popover with each notice showing, the About window, and the preview
      hint, in German.
- [x] The invariant: a unit test reads every String Catalog in the project and fails on any entry
      whose German is missing, marked stale, or marked needs-review, and on any English entry
      that doesn't appear as a key. Unit test.
- [x] `scripts/check` passes.
- [x] No `[COPY - Jake]` marker remains in shipped copy.

## Design
**String Catalogs, not `.strings` files.** Three `.xcstrings` files in `OnCue/`:
`Localizable.xcstrings` for code, `Main.xcstrings` for the storyboard, and `InfoPlist.xcstrings`
for the bundle name, copyright and the two usage descriptions. The project gains `de` in
`knownRegions`, `SWIFT_EMIT_LOC_STRINGS` so the compiler emits the code strings, and
`LOCALIZATION_PREFERS_STRING_CATALOGS`. The storyboard stays in `Base.lproj`, once. The build
compiles the catalogs into `de.lproj` (`Main.strings`, `Localizable.strings`, a
`Localizable.stringsdict` for the plurals, `InfoPlist.strings`) and an `en.lproj` holding only the
English stringsdict.

**How the catalogs are filled from the command line.** Xcode's IDE syncs catalogs on build;
`xcodebuild` does not, so the keys came from `xcodebuild -exportLocalizations` (an `.xcloc` with
every code, storyboard and Info.plist string), the German went into a copy of that export, and
`xcodebuild -importLocalizations` wrote it into the code and Info.plist catalogs. The import
writes the storyboard's German as a legacy `de.lproj/Main.strings`, so the storyboard catalog was
generated from the export instead (key `ObjectID.title`, the exporter's comment, English stored as
the source value) and the legacy file removed. The catalog is what the build reads; that's proved
by the round-trip test. The export normalises multi-argument strings to positional specifiers
(`%1$@`), so the German for those was matched by key, not by source text.

**Code strings.** Every user-visible literal is `String(localized:comment:)` with the English as
the key and a comment saying where it shows and what the placeholders are. Strings that never
reach a user (defaults keys, file names, log lines, queue labels, the measurement file) are left
alone; so is the preview window's title, which is camera names joined by a plus sign. Recording
file names stay `en_US_POSIX`, including the frame-loss suffix.

**Plurals.** The deleted-recordings notice and the four failure notices are catalog entries with
`one` and `other` variations in both languages, in place of the `count == 1 ?` branches. The
trigger-cost line is not pluralised: it never shows fewer than three recordings.

**The failure notice.** One entry per failure, each a whole sentence with its own singular, so
German can order the words its own way. The text moved from the popover to
`RecordingFailure.notice(count:)`, beside the cases and inside the test target.

**The hidden main menu.** The storyboard carries the Xcode template's main menu, 134 items,
which an `LSUIElement` app never shows; it exists so Edit-menu shortcuts work in text fields.
Those entries are marked `shouldTranslate: false` and left in English. The invariant allows that
only for storyboard entries whose class is `NSMenu` or `NSMenuItem`, so nothing else can hide
behind the flag. Strings that are the same in German (OnCue, numbers, the copyright, OK,
`Version %@`) carry the English value as their German, unmarked: nothing was proposed.

**Sizing.** German runs about a third longer than English. The fourteen storyboard labels that
clipped now truncate with an ellipsis, so an overflow is visible rather than silent. Two Settings
captions had no room to grow: "seconds to include from before activity starts" had no trailing
constraint at all and "GB of recordings to keep" was pinned to the window edge; both now have a
trailing greater-than-or-equal constraint like the first caption, so a longer caption widens the
window (Settings sizes itself from `fittingSize`). The popover's notice and trigger-cost heights
were already measured from `sizeThatFits`; nothing to change there. The schedule row's weekday
checkboxes use `veryShortWeekdaySymbols`, one letter in German too.

**The invariant.** `LocalizationTests` parses each `.xcstrings` from the source tree. For every
key not marked do-not-translate it requires a `de` whose state is `translated` and, where the
English has plural variations, the same set in German. Missing, `needs_review` and `stale` fail
with the key named. Two more tests close the gaps the catalogs can't see: every titled object in
the storyboard XML has a key in the storyboard catalog, and every `String(localized:)` literal in
the sources matches exactly one key in the code catalog (interpolations standing for one specifier
each). A round-trip test reads the German from the app's own `de.lproj` and compares it with the
catalogs, for a code string, a storyboard string and a usage description, and formats the plurals
through the compiled stringsdict at one and at many.

**What the invariant does not prove.** That the German is correct, idiomatic, or the right
register (Sie throughout, as macOS itself uses). Only Jake can read that, and only on screen. The
spec's Verification lists what he looked at.

**Copy.** All German strings are copy: Claude proposes them in the catalog with `[COPY - Jake]`
appended to each value, Jake edits and strikes. The English keys are the existing strings and stay
as they are. The catalog entries carry the marker in their value, so `scripts/ship-check` finds
them the same way it finds everything else.

**Alternatives rejected.** `.strings` plus `.stringsdict`: the old format, hand-maintained, with
no state per entry, so nothing to check. Per-language storyboards: a second copy of every
constraint to keep in step. A translation service or automated pass for further languages: outside
this spec's non-goals.

## Gates
- [x] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [x] On this Mac, in German: every window and the popover with each notice showing, nothing
      clipped, nothing English, the permission prompt in German on a fresh TCC state
- [x] On this Mac, in English: the popover and Settings unchanged

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

Copy to convey: every existing English string, in German, in the formal register, with OnCue's
own names (OnCue, the recordings folder) kept; the two permission prompts saying what the camera
and microphone are for.

## Tasks
- [x] Add the three catalogs and `de` to the project; migrate the storyboard and `Info.plist`
- [x] Wrap every user-visible code literal in `String(localized:)` with comments
- [x] Plural entries for the count strings; one entry per case for the failure notice
- [x] `LocalizationTests`: the invariant and the compiled-bundle round trip
- [x] German values in every catalog (marked copy)
- [x] Sizing: the clipping labels; the popover heights were already measured
- [x] Help page note that the app is in German on a German Mac (marked copy)
- [x] The manual checks, in German and in English

## Verification
- **Built (2026-09-23):** three catalogs, `de` in the project, 62 code strings, 28 visible
  storyboard strings, 4 Info.plist strings, all with German; 134 hidden main-menu entries marked
  not to translate. Five plural entries in both languages. The failure notice is
  `RecordingFailure.notice(count:)`, one sentence per case. `LocalizationTests`, ten tests: the
  invariant over all three catalogs; do-not-translate allowed only for storyboard menu classes;
  every storyboard title in the catalog (an empty title and a pop-up cell's excluded, as the
  exporter excludes them); every `String(localized:)` literal matching exactly one key; the
  pattern helper; the German read back from the built app's `de.lproj` for a code string, a
  storyboard string and a usage description; the plurals through the compiled stringsdict at one
  and at many; the failure and deleted notices unchanged in English at 1, 2, 3 and 5; the weekday
  from a `de_DE` calendar. Clean build, 312 tests, none failing. The built app's `de.lproj`
  holds `Main.strings`, `Localizable.strings`, `Localizable.stringsdict` and `InfoPlist.strings`.
- Not yet seen: anything on screen. The German itself, the register, the sizing of every window in
  German and the unchanged English are Jake's checks. Run the Debug build with
  `-AppleLanguages '(de)'` to see it without changing the Mac's language.
- **Read (Jake, 2026-09-23):** every German value in the three catalogs and the help note; all
  correct as proposed, markers struck. `scripts/check` passes with them gone.
- **Checked on this Mac (Jake, 2026-09-23):** the app run in German, every window and the popover
  with its notices, nothing clipped, nothing English; and in English, unchanged. Manual checks all
  good.

## Open questions
1. Resolved (Jake, 2026-09-23): Sie throughout, including the permission prompts and
   notifications. macOS itself says Sie, and OnCue's prompts sit beside the system's dialogs.
2. Resolved (Jake, 2026-09-23): the App Store listing's German is a later step on its own, not
   part of this spec. It's a localization row in App Store Connect, edited in the browser,
   independent of the binary.
3. Resolved (Jake, 2026-09-23): the English strings stay the catalog keys. An English edit makes
   its German stale and fails the invariant until the German is revisited. That coupling is the
   point: it's what says the German needs a look, with one reader.
4. Resolved (Jake, 2026-09-23): after the release carrying 0040, 0041 and 0042. This touches
   every string and several layouts, and is checked on its own.

## Closure
Shipped in 4.11 (2026-09-23), direct and tap, build 891 uploaded to App Store Connect by the
release script's store section.
