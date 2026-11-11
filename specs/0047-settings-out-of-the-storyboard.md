---
title: Settings out of the storyboard
status: draft
created: 2026-09-23
commits: <filled in as work lands>
---

## Problem
The Settings window is half storyboard, half code. The schedule section (0038) is built in code
under a storyboard view whose labels, fields, pop-ups, checkboxes and 58 constraints live in
`Main.storyboard`. That half costs something every time it's touched: outlets registered by
hand, layout edited as XML (0043 added trailing constraints by editing attribute strings), and a
String Catalog of its own keyed by object ID that Xcode's sync can't see, so every entry is
`manual` and a stray Xcode build deleted 134 of them (2026-09-23, noted in `CLAUDE.md`). The
code half has none of those problems: its strings are ordinary `String(localized:)` keys, its
layout is readable, and its rows are made by a function that can be tested.

## Non-goals
- Redesigning Settings. Same controls, same order, same words, same window. This is a move,
  not a change; if it looks different, that's a bug.
- The popover, the preview window, About, or the hidden main menu. Each is its own step; the
  storyboard and its catalog go when the last scene leaves, not in this spec.
- SwiftUI. The schedule section is AppKit in code and works; the rest joins it.
- New settings. Nothing is added or removed.

## Behaviour (acceptance criteria)
- [ ] The Settings window is built in code: window (title, floating level, transparent title
      bar, not released on close) and every control, with the storyboard's two Settings scenes
      deleted. Manual check that it opens from the popover menu as before.
- [ ] The inventory is identical. A fixture, recorded from the storyboard version before the
      move, lists every control top to bottom: kind, label or title, defaults key, formatter
      range, target action. A unit test builds the code version and compares. The fixture is
      committed first, on its own, so the comparison is against what shipped.
- [ ] Every behaviour the controller has stays: camera and microphone menus filled from
      capture, the folder row and its note (0034), Choose… and Reset (0017), open-at-login and
      its approval flow (0015), arm-at-login (0018), the number fields' ranges and the
      out-of-range alert, the schedule section (0038), the fresh-start clear (0037), the
      window sizing to fit. Existing unit tests unchanged and green; manual check of each.
- [ ] The strings move, they don't change. The twelve Settings entries leave the storyboard
      catalog and their English becomes the key in the code catalog, with the same German
      carried over. No copy is proposed, so no marker; the localization invariant stays green
      and the German window reads exactly as before. Unit test (0043's invariant); manual check
      in German.
- [ ] The window looks the same. Screenshots before and after, at the same size, in English
      and German, side by side. Manual check; small differences in spacing from the layout
      moving to a grid are allowed, anything that reads differently is not.
- [ ] `scripts/check` passes.
- [ ] No `[COPY - Jake]` marker remains in shipped copy.

## Design
**Record first.** Before anything moves, a test walks the storyboard-built Settings view and
writes its inventory to `OnCueTests/Fixtures/settings-inventory.json`: for each control in
visual order, its class, its title or label, the defaults key it reads or writes, its number
formatter's minimum and maximum, and the selector it sends. That file is committed alone. The
same walker then runs against the code-built view, and the test compares. The walker is the
invariant; the screenshots are the eye.

**Build.** `SettingsView` (or the controller's `loadView`) makes the window's content the way
the schedule section already does: an `NSGridView` for the label-and-control rows the storyboard
laid out with constraints (Camera, Second camera, Microphone, the three number rows, the folder
row), `NSStackView` for the checkboxes and the schedule section under it. Outlets become stored
properties; `@IBAction`s become target-action wired in code; the one binding (Open Preview
Window at Launch to `values.openPreviewWindowAtLaunch`) becomes `bind(_:to:withKeyPath:)` on
`NSUserDefaultsController.shared`. Number formatters are made in code with the storyboard's
ranges. `SettingsWindowController.freshController()` makes an `NSWindow` in code with the
storyboard's attributes and the view controller as content; the popover menu's lazy property
doesn't change.

**Sizing.** The storyboard's 480-point width becomes the grid's width; height comes from
`fittingSize`, as it does today after the schedule section rebuilds.

**Strings.** Each storyboard title becomes `String(localized:)` with the same English and a
comment. The German is moved from the storyboard catalog entry to the new code-catalog entry
by script, value for value, so nothing is retranslated. The storyboard catalog loses those
twelve entries and keeps the popover's, About's, the preview's and the menu's.

**What doesn't move.** The controller's logic: device menus, folder handling, login item,
number-field validation, the schedule section. It's the same file with `viewDidLoad` building
what the storyboard used to.

**Alternatives rejected.** SwiftUI: a second UI toolkit for one window. A xib instead of a
storyboard: same XML, same catalog problem. Leaving it: every future Settings change pays the
XML tax and the catalog workaround stays.

## Gates
- [ ] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [ ] The inventory test against the committed fixture
- [ ] On this Mac: Settings in English and German, before and after, side by side; every
      control tried once

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

No new copy: every string moves verbatim.

## Tasks
- [ ] The inventory walker and the fixture from the storyboard version, committed alone
- [ ] The window and view in code; the storyboard scenes removed
- [ ] The strings moved, storyboard catalog trimmed, German carried over by script
- [ ] The inventory test green against the fixture; the existing suite green
- [ ] Screenshots and the manual checks

## Verification
Nothing yet.

## Held as a draft (Jake, 2026-09-23)
Not worth a day on its own. The ongoing cost is about an hour of XML per Settings change that
touches layout and a hand-added catalog entry per new string, and the catalog workaround is
stable. The payoff is developer-side only, and the catalog itself goes only when the popover,
the preview, About and the hidden menu move too. Comes back when Settings next needs a real
change, so the move rides on it, or when the whole storyboard is to be retired.

## Open questions
1. Pixel-identical, or the same to the eye? A grid won't reproduce 58 hand-placed constraints
   to the point; the draft allows spacing to differ and nothing else. The alternative is to
   copy every constraint into code, which keeps the layout exact and the XML tax in a new form.
2. The About window is thirty lines of storyboard and would take an afternoon on the same
   pattern. In this spec, or its own? The draft says its own: one scene per step keeps each
   diff readable, and the storyboard's end is a milestone worth its own commit.
