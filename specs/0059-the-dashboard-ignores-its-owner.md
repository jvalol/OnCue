---
title: The dashboard ignores its owner
status: abandoned
created: 2026-10-03
commits: 6032135 (approval); the implementation was never committed
---

## Problem
Every download the dashboard has counted landed on a release day, one per release, and the page
views peak on the days the site was being worked on. That's Jake checking his own releases,
and he can't tell it from a stranger because the counter has no idea who he is. A dashboard
that can't subtract its owner answers "is anyone out there" with "you are". `scripts/check-tap`
already sends a user-agent the counter skips; the browser Jake reads the site with sends
nothing of the kind.

## Non-goals
- No tracking of anyone else. Nothing changes for a visitor: no cookie, no script, no
  fingerprint, the privacy page's promises as they are.
- No login for the site. The dashboard already has a password; this reuses that moment.
- No retroactive cleanup. The six downloads and the views so far stay in the table; the
  "counting since" line already says when the numbers started meaning something, and a second
  such line isn't worth the code.

## Behaviour (acceptance criteria)
- [ ] Opening the dashboard with the right password sets a cookie in that browser, scoped to
      the site, that lasts a year. Manual check with `netlify dev`: the response carries it.
- [ ] A request carrying that cookie, page or zip, is not counted. Manual check with
      `netlify dev`: a fetch with the cookie adds no row, the same fetch without it does.
- [ ] The dashboard says, at the top, whether the browser it's open in is being counted, so the
      state is visible rather than remembered. Manual check.
- [ ] The privacy page says that one cookie exists, that only the site's owner gets it by
      signing into the dashboard, and that it exists to keep the owner out of the counts. The
      sentence is copy and arrives marked.
- [ ] `scripts/check` passes (the store self-tests and the TypeScript check in it).
- [ ] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- **The cookie.** `dashboard-auth.ts` already runs on every `/dashboard/` request and checks
  the password. On a request that passes, it adds `Set-Cookie: oncue-owner=1; Path=/; Max-Age=
  31536000; Secure; SameSite=Lax` to the response. Not `HttpOnly`, so the dashboard page can
  read it and say so. The value is a constant: the cookie says "owner", not who; the password
  is what proved it.
- **The counter.** `count.ts` returns early when the `cookie` header contains `oncue-owner=1`,
  beside the existing check-tap and bot checks, before anything is read from the request.
- **The dashboard.** One line under the title: counted or not, from `document.cookie`.
- **Rejected:** a query parameter (nothing Jake types or bookmarks reliably carries it to the
  zip link); a browser extension or a custom user-agent (a setup step on every browser and
  Mac); excluding by country or by time of day (guesswork that would exclude someone else).

## Gates
- [ ] `scripts/check` passes (no copy markers, clean build, unit tests green)
- [ ] `netlify dev` checks above, recorded in Verification

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

## Tasks
- [x] The cookie on a passed dashboard request; the counter's early return
- [x] The dashboard's counted-or-not line
- [x] The privacy page sentence, marked
- [ ] The `netlify dev` checks

## Verification
Built on 2026-10-03 and never committed: the shared cookie check, the cookie on a passed
dashboard sign-in, the counter's early return, the dashboard's counted-or-not line and the
privacy sentence, with the served site checked locally. Discarded the same evening.

## Abandoned (Jake, 2026-10-03)
Not worth it. Every download so far landed on a release day, one per release, and Jake reads
that correctly without help: he already knows when it's him. What the cookie would buy is a
chart that's right without remembering; what it would cost is a permanent exception on a
privacy page whose strength is having none. "No cookie" with an asterisk is weaker than "no
cookie", for a reader who isn't the one person the exception is for. The decisions above stand
as the design if a second reader of the dashboard ever makes it worth revisiting.

## Open questions
1. Resolved (Jake, 2026-10-03): the cookie, set by a dashboard request that passed the
   password. It rides on every page and zip request from that browser, including the download
   button, and costs no habit beyond opening the dashboard once per browser. The privacy page
   gains one sentence: visitors get no cookie, the owner gives himself one.
2. Resolved (Jake, 2026-10-03): a year, set again on every dashboard sign-in, so a browser in
   use never sees it run out. A session cookie is the right length for a visitor and the wrong
   one for this, since it would be gone by the next release day.
3. Resolved (Jake, 2026-10-03): each browser and Mac needs the dashboard opened once, and the
   dashboard's own line says whether the browser it's open in is counted. One mechanism,
   visibly stated, rather than a second signal for browsers that haven't signed in.
