---
description: List the specs in specs/ with their status
---
Read every `specs/NNNN-*.md`, parse `title` and `status` from its frontmatter only (not the body), and print a compact table sorted by number: `#  ·  status  ·  title`. Call out anything `draft` or `approved` so it's clear what's waiting on Jake and what's ready to build.
