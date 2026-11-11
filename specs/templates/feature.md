---
title: <what changes, in a phrase>
status: draft   # draft → approved → shipped | abandoned
created: <YYYY-MM-DD>
commits: <filled in as work lands>
---

## Problem
Why this change exists: the current behaviour and why it's wrong or missing. One short paragraph.

## Non-goals
What this deliberately does not do, so the implementer knows where to stop.

## Behaviour (acceptance criteria)
Observable yes/no statements, the definition of done. Each maps to a unit test or, where the
behaviour needs a real camera or the menu bar, a manual check named in Verification.

- [ ] ...
- [ ] No `[COPY - Jake]` marker remains in shipped copy.

## Design
The approach. Files and types touched, threading and queue concerns, alternatives rejected.
A sketch, not a novel.

## Gates
- [ ] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [ ] <anything specific to this change>

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

## Tasks
- [ ] ...

## Verification
What was actually checked, filled in as it happens: tests, a run on this Mac, a recording on disk.

## Open questions
Anything unresolved. Empty is a good sign.
