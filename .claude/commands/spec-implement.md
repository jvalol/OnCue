---
description: Implement an approved spec, keeping it current
argument-hint: <spec number or slug>
---
Implement a spec.

Target: $ARGUMENTS

1. **Locate.** Match against `specs/NNNN-*.md` by number or slug. If nothing matches or it's ambiguous, list `specs/` and ask.
2. **Check approval.** If `status` is still `draft`, stop and ask Jake to approve it (or to resolve its open questions). Don't implement a draft.
3. **Read it fully.** If the Behaviour, Design, or Tasks look stale or wrong against the code, raise it with Jake before writing code.
4. **Work the tasks in order.** Write the test for each acceptance criterion alongside the code. Check off tasks and record decisions in the spec as you go; the file should never lag the code.
5. **Gate.** Run `scripts/check`. It must pass.
6. **Leave it for Jake.** Changes land in the working tree, uncommitted, for Jake to review. When he asks for a commit, the spec file goes in its own commit, never mixed with implementation; scope every commit with `git commit -- <paths>`.
7. **Close out** once it's committed: `status: shipped`, `commits:` filled in, Verification says what was actually checked (including any manual check on the real app). If it's dropped instead, `status: abandoned` with the reason.
