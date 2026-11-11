---
title: The engine as a package
status: draft
created: 2026-09-23
commits: <filled in as work lands>
---

## Held as a draft (Jake, 2026-09-23)
Not now. Twenty files (about 2,200 of 6,400 lines: the Metal kernel and renderer, zones,
schedule, disk budget, trigger cost, pre-roll, frame loss, recordings folder, sample ring, and
the smaller rules) have no AppKit in them, and only two reference the app (both take the
manager's `ArmState`, which would move). The boundary is nearly real already. What a package
would add: new engine files without a hand-written pbxproj entry, a compiler-enforced boundary
instead of a grep, and the first step toward any second target. What it costs: a day of
plumbing (the shader library into the package bundle and the renderer's lookup with it, the
engine's tests into a package test bundle, the gate running both suites, the archive and store
export checked with a local package), one more pbxproj section to keep right, and nothing a
user sees. The big benefit needs a second product, and the platform decision is no second
platform until demand. Comes back the day a second target is decided, as its first step.

## Problem
The engine and the Mac app share one target and one project file. Nothing enforces the line
between "what a camera does" and "what a Mac app does" except a grep, and every new engine
file is a hand-edited project entry.

## Non-goals
- A second target. This is the step before one, not one.
- Changing any behaviour. Same tests green, same app bundle.

## Behaviour (acceptance criteria)
- [ ] An `OnCueEngine` Swift package under the repo, a local dependency of the app, holding
      the twenty AppKit-free files, the shader, and their tests. Unit tests unchanged and green
      in the package's test bundle.
- [ ] The app builds, archives and exports for the store with the package. `scripts/release`
      unchanged or adjusted; manual check on a release.
- [ ] `ArmState` lives in the engine; the manager uses it from there. Existing tests unchanged.
- [ ] `scripts/check` runs both suites. Gate.

## Design
Sketched only: `Package.swift` with one library target and one test target, platforms macOS 14;
the shader compiled as a package resource and loaded with `makeDefaultLibrary(bundle:)`;
`ArmState` moved to `Engine/ArmState.swift`; the app's project gains the package reference and
loses the twenty file entries; `MotionDetectRendererTests` run against the package's library
rather than the app's.

## Gates
- [ ] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [ ] A release archived and exported for the store with the package in it

## Tasks
- [ ] Not started

## Verification
Nothing yet.

## Open questions
1. Whether the renderer's Debug-only measurement hook (0041) stays in the package or moves out.
2. Whether `scripts/check` runs the package tests through the app scheme or a second invocation.
