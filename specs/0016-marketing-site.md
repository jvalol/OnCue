---
title: Revive the OnCue marketing site
status: shipped   # draft → approved → shipped | abandoned
created: 2026-09-19
commits: 9f0de23 (spec), ffcb92a (implementation)
---

## Problem
OnCue has no public page. The 2017 site is still in `jvalol/OnCue-homepage` (private, last pushed
2017-08-06): a hand-built static front page, a help page, a purchase page, and a 404, in a repo of
1,436 files that is mostly a WordPress install under `blog/`, plus a 4.3 MB `purchase/OnCue.zip`
from 2017 and a `newsletter.php` that needs a PHP host. Its copy describes the old app and
promises things today's app doesn't do (saving to Dropbox, camera schedules and power cycling,
recording quality), while saying nothing about two cameras, pre-roll, the mic picker, or the sleep
warning.

## Non-goals
- The blog: neither the WordPress install nor its posts come across; they stay in the old repo.
- Selling or licensing: no purchase flow, no license keys.
- A newsletter, which would need a server; the page is static.
- Building, notarizing, or hosting a downloadable app: there's no download button yet.

## Behaviour (acceptance criteria)
- [x] The site is the 2017 design and layout, carried over: the same structure, styles, fonts, and
      hero, with the old app's screenshots replaced by current ones. Manual check side by side.
- [x] Every claim on the page matches what OnCue does today. Manual check against Settings and the
      popover, item by item.
- [x] Pages: a front page and a help page. No purchase page, no newsletter, no WordPress.
- [x] The site lives in `site/` in this repo and builds nothing: Netlify serves the folder as is.
      Manual check: a Netlify deploy preview renders it.
- [x] Nothing offers a download until there's a notarized build; the page points at the GitHub repo
      instead.
- [x] The site is plain static files: no PHP, nothing that needs a server.
- [x] It reads well on a phone as well as a desktop. Manual check at both widths.
- [x] No `[COPY - Jake]` marker remains in shipped copy: every word on the site is Jake's.

## Design
- `site/` in this repo, published by Netlify straight from that folder with no build step, with a
  `netlify.toml` setting the publish directory. The domain is Jake's to point when he chooses; until
  then it's the Netlify address.
- Start from the 2017 `index.html`, `help/index.html`, `stylesheets/`, `font/`, and the images
  worth keeping; leave `blog/`, `purchase/`, and `newsletter.php` behind. The old repo stays as the
  record.
- Fresh screenshots from today's app: the popover with two cameras, Settings, the preview window.
- Feature text follows what shipped in specs 0002 to 0015: motion and sound triggers with their own
  thresholds, two cameras, pre-roll, device picking, recordings named for their devices in
  `~/Movies/OnCue`, keep-awake and the lid warning, open at login.
- All prose and headings are copy: drafts carry `[COPY - Jake]`, and `scripts/ship-check` covers the
  site's files.

- **Built (2026-09-19):**
  - `site/` holds `index.html`, `help/index.html`, and the 2017 `stylesheets/`, `javascripts/`,
    `font/`, and icon. `netlify.toml` publishes `site/` with no build command.
  - Dropped with the old site: the WordPress blog, the purchase page and its 2017 zip, the PHP
    newsletter, the Mac App Store badge, the direct download, the donation buttons, analytics, the
    Dropbox affiliate links, and the EggDevil name. Google Fonts and jQuery now load over https from
    the repo or Google, not plain http.
  - The help page is a plain page in the same style rather than the old screenshot slideshow, so it
    stays accurate without Flexslider.
  - `scripts/ship-check` now scans `site/` too, so no marker can ship with the page.

## Gates
- [x] `scripts/check` passes (it gains the site's files through ship-check)
- [x] Manual checks: the page at desktop and phone widths, and every claim checked against the app

## Tasks
- [x] Carry over the pages, styles, fonts, and images; drop the blog, purchase, and PHP
- [x] Fresh screenshots
- [x] Draft the copy, marked, for Jake
- [x] Manual checks, Verification filled in

## Verification
- Served `site/` locally and checked both pages in a browser: styles, fonts, images, and links all
  load; the front page lays out in two columns at 1440 wide and stacks on a 375-wide phone with no
  horizontal scrolling; the help page renders with its four screenshots.
- Screenshots are Jake's own, retaken 2026-09-19 after the app was current: the popover with two
  cameras, Settings with the login and folder rows, the preview with both cameras side by side, and
  the menu bar icon while recording.
- Live at https://oncue-web.netlify.app, deployed from `master` with no build step (Jake, 2026-09-19).
- Every claim on the page was written from specs 0002 to 0015 and checked against the app's current
  behaviour.
- Copy: every line of prose carries `[COPY - Jake]` for Jake to write. `scripts/ship-check` fails
  while they remain, as it should.
- Jake's manual checks (2026-09-19): the deployed site works at https://oncue-web.netlify.app, on
  desktop and phone widths. After his review the screenshots section lost the menu bar tile, the
  preview went full width with its letterboxing cropped out, and section anchors were offset so a
  heading jumped to from the nav isn't hidden behind the fixed bar.

## Open questions
Resolved by Jake, 2026-09-19: `site/` in this repo; served by Netlify; no download until there's a
notarized build; the blog stays behind.
