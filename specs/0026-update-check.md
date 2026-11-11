---
title: Tell people a newer OnCue exists
status: abandoned   # draft → approved → shipped | abandoned
created: 2026-09-20
commits: <filled in as work lands>
---

## Abandoned (Jake, 2026-09-20)
No in-app check. The guarantee is worth more than the mechanism: OnCue has no network entitlement,
so "no network" is something macOS enforces rather than something the app promises, and that is a
real part of what OnCue is. Spending it so the app can tell you about itself is a bad trade for a
security camera.

Releases get announced on Mastodon, where the account is already verified against the site, and
through an RSS feed of the changelog. Both reach anyone who asked to be reached and cost the app
nothing. Fewer people hear, and only the ones who chose to; that's the price, and it's smaller
than the one above.

The rest of this file is the spec as written before that decision, kept because the reasoning is
the point. If an in-app check is ever revisited, open question 1 is the one to re-argue, not the
implementation.

## Problem
There have been three releases in two days and no way for anyone running OnCue to learn about any
of them. It's a menu bar app that can sit untouched for months, so "check the website" is not a
mechanism. Spec 0020 listed automatic updates as a non-goal, "worth its own spec once there's
something to update from", and that's now true three times over.

## What it costs
`OnCue.entitlements` has no `com.apple.security.network.client`. The sandbox permits movies,
user-selected files, the camera and the microphone, and nothing else. OnCue cannot open a network
connection: not by policy, by enforcement.

That is what the site means by "No account, no cloud, no network", and what the README means. An
update check turns an enforced guarantee into a promise, permanently, and makes that copy false as
written. A security camera is exactly the kind of app where someone might check the entitlements
rather than take a sentence's word for it, and today that check rewards them.

So the first question isn't how to build this. It's whether the guarantee is worth more than the
mechanism, and if it isn't, saying so deliberately rather than sliding into it.

## Non-goals
- Downloading or installing an update. Telling someone a new version exists is a smaller promise
  than replacing a signed binary on their Mac, and it can be decided separately.
- Anything that identifies a user. No account, no identifier, no counting installs.
- Telling people about anything other than a new version.

## Behaviour (acceptance criteria)
- [ ] OnCue says when a newer version exists, and how to get it. Manual check.
- [ ] It never says so when the running version is current or newer. Unit test on the comparison.
- [ ] A check that fails, times out, or returns nonsense is silent: no error, no dialog, no
      repeated attempts. Unit test on the rule, plus a manual check with the network off.
- [ ] Nothing about the user or their Mac is sent beyond what fetching a URL unavoidably reveals.
      Manual check against the actual request.
- [ ] The site's "no network" wording matches whatever the app now does. Manual check.
- [ ] `scripts/check` passes.
- [ ] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- A version comparison is a pure function and the only part worth testing: "4.10" is newer than
  "4.9", and neither string comparison nor a float gets that right.
- Whatever is fetched should be the smallest thing that answers the question: a file on the site
  holding the current version, written by `scripts/release` so it can't drift from what's actually
  downloadable, the way the changelog and the version line already can't.
- `scripts/release` gains that file, and a check that it matches, alongside the checks it already
  makes on the site.
- Where it appears: the popover has a notice line under the arm state, already used by the lid
  warning and the sleep gap, and a menu behind the gear.

## Gates
- [ ] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [ ] With the network unreachable, OnCue behaves exactly as it does today

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

## Tasks
- [ ] Decide whether to add the entitlement at all (Open questions)
- [ ] The version comparison, with tests
- [ ] The current-version file, written and checked by `scripts/release`
- [ ] The check itself, and where it surfaces
- [ ] Reword the site and README to match what the app now does
- [ ] Manual checks, Verification filled in

## Verification
Filled in as it happens.

## Open questions
1. **Is the entitlement worth it?** Adding `network.client` costs a guarantee that currently can't
   be broken, for a convenience. The alternative is no in-app check at all: announce releases on
   Mastodon, where the account is already verified against the site, or an RSS feed of the
   changelog, which costs the app nothing and reaches anyone who wants telling. That reaches fewer
   people, and only those who thought to follow. Everything below only matters if the answer here
   is yes.
2. **Automatic, or only when asked?** A "Check for Updates" menu item means no traffic unless
   someone asks for it, which is a much smaller claim to make, and no background behaviour to
   explain. Checking on its own actually reaches the person who forgot OnCue exists, which is the
   one this spec is for.
3. **What does the request reveal?** Fetching a URL sends an IP address and a timestamp to
   whoever serves it, which is Netlify. If the version travels in the URL or the user agent, it
   also says which version is running. None of that is nothing, and the honest thing is to write
   down what's sent rather than call it anonymous.
4. **Sparkle, or a few lines?** Sparkle is the standard, handles signature verification, and would
   be the answer if this ever installed updates. It's also a dependency, and this repo has none
   since CocoaPods came out. Fetching one small file and comparing two strings needs no framework,
   and the non-goal above says installing is out of scope.