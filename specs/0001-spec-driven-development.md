---
title: Spec-driven development
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-19
commits: 50e65c2 (spec), b9c8b2b (implementation)
---

## Problem
OnCue changes have been landing straight from chat, with the intent living only in the
conversation. Nothing records what a change was for or how it was checked, and there's no single
command that proves the app still builds and passes its tests.

## Non-goals
- Retroactive specs for the work already shipped on 2026-09-18 and 2026-09-19.
- CI. Pushing stays manual and there's no hosted runner.
- Any change to the app itself.

## Behaviour (acceptance criteria)
- [x] `CLAUDE.md` states the workflow, the working rules, the gate, and the known quirks.
- [x] `specs/README.md` and `specs/templates/feature.md` define the spec shape and the
      capability line; `/spec-new`, `/spec-implement`, and `/spec-list` exist.
- [x] `scripts/ship-check` exits 1 and names the file and line when a `[COPY - Jake]` marker is
      in `OnCue/` or `README.md`, and exits 0 otherwise. Manual check: add a marker to the
      README, run it, revert.
- [x] Project memory lives in `.claude/memory`, tracked, with
      `~/.claude/projects/-Users-jake-Developer-oncue/memory` a symlink to it. Manual check:
      `ls -la` shows the link.
- [x] `scripts/check` runs ship-check, then a clean build and the unit tests, exits non-zero on
      any failure, and leaves `CFBundleVersion` unchanged.

## Design
jvalol's mechanics (numbered specs, the three slash commands, a Gates and Verification section)
with PopsicleBoat's rules (approval before code, criteria mapped to tests, the capability line,
spec and implementation never in the same commit, apply-don't-commit). One lane, since OnCue has no editorial side.
`scripts/check` plays the role of PopsicleBoat's `mix check`. It restores the build number
because the Run Script phase bumps it on every build.

Memory follows the jvalol and PopsicleBoat arrangement: canonical in the repo, symlinked from
`~/.claude/projects`, committed by Claude with a scoped pathspec. `.gitignore` tracks `.claude/`
except machine-local settings and worktrees.

## Gates
- [x] `scripts/check` passes

## Tasks
- [x] `scripts/ship-check` and `scripts/check`
- [x] `specs/README.md`, `specs/templates/feature.md`
- [x] `.claude/commands/spec-new.md`, `spec-implement.md`, `spec-list.md`
- [x] `CLAUDE.md`
- [x] This spec as the worked example
- [x] `.claude/memory` with the symlink, a `.gitignore` for local Claude state, the first memories

## Verification
- `scripts/ship-check` with a marker temporarily appended to the README: exit 1, reported
  `README.md:2`. Reverted, exit 0.
- `scripts/check`: 9 tests passed, exit 0, `Info.plist` unchanged afterwards. Run again before
  the implementation commit, same result.
- `~/.claude/projects/-Users-jake-Developer-oncue/memory` is a symlink to `.claude/memory`.

## Open questions
None. Resolved at approval (Jake, 2026-09-19): strict spec commit separation, as in PopsicleBoat;
memory in the repo, as in jvalol and PopsicleBoat.
