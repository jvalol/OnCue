---
description: Scaffold a new spec in specs/
argument-hint: <short description>
---
Scaffold a new spec. Do NOT start implementing; that waits for Jake's approval and `/spec-implement`.

Request: $ARGUMENTS

1. **Does it need one?** Per `specs/README.md`, a bug fix or mechanical change doesn't. If this is one, say so and stop.
2. **Number.** The highest `NNNN` prefix among `specs/NNNN-*.md` plus one, zero-padded to four digits.
3. **Slug.** Lowercase, hyphen-joined, short, no filler words.
4. **Create** `specs/NNNN-slug.md` from `specs/templates/feature.md`. Fill `title`, `status: draft`, and `created:` from `date +%F`.
5. **First pass.** Draft what you know. Acceptance criteria are yes/no statements, each naming the test or manual check that proves it. Put anything that needs Jake's decision under Open questions. Keep it lean.
6. **Index.** Add a row to the table in `specs/README.md`.
7. Report the path, a two-line summary, and the open questions. Stop there; the spec lands uncommitted for Jake to read.
