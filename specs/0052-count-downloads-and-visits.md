---
title: Count downloads and site visits, and show them on a private dashboard
status: shipped
created: 2026-09-25
commits: cf00d26 (approval), 3dd13cf (implementation, squashed from the Netlify agent's branch; deployed by the push)
---

## Problem
Nobody knows how many people download OnCue, through which channel, or which versions they
take. `site/downloads` serves the zips as plain static files and brew fetches the same URLs, so
every download goes by without being counted. The site has no idea whether anyone reads the help,
the changelog or the privacy page either. Jake asked for a dashboard of user engagement and zip
downloads.

The app can't be where the counting happens. It runs sandboxed with no network permission, and
the privacy page promises it "collects nothing, sends nothing, and has no way to." The only
honest place to count is the site, on requests it is already serving.

## Non-goals
- Nothing in the app. No telemetry, no update ping, no network entitlement. The privacy promise
  about OnCue stands word for word.
- No client-side tracking on the site: no JavaScript beacon, no cookies, no fingerprinting,
  no third-party analytics service.
- No personal data kept. No IP addresses, no full user-agent strings, nothing that ties two
  requests to one person. The data is counts, not visitors.
- No App Store figures. App Store Connect already reports those; this covers the site and brew.
- No public stats page.

## Behaviour (acceptance criteria)
- [ ] A request for `/downloads/OnCue-<version>.zip` is recorded with the version, the time, the
      channel (`brew` when the user-agent is Homebrew's, `browser` otherwise), and the country
      Netlify reports. The zip is still served exactly as before. (Manual: download through the
      browser and with `brew fetch`, then look at the dashboard.)
- [ ] A failure to record never fails or slows the download: if the database is unreachable, the
      zip is still served. (Manual: point the function at a bad connection string on a deploy
      preview.)
- [x] `scripts/check-tap`'s own zip fetch isn't counted. It sends an identifying user-agent that
      the function skips. (Manual: run `scripts/check-tap`; the count doesn't move.)
- [x] A request for a site page (`/`, `/help/`, `/changelog/`, `/privacy/`) is counted by path,
      day and country, with the referring host when there is one. Asset requests, bots that say
      so, and the redirect from the old hostname aren't counted.
- [x] No row stores an IP address or a full user-agent string. (Read `db/schema.ts`.)
- [x] `/dashboard/` shows, for a chosen range (7, 30, 90 days, all time): total downloads,
      downloads per day split by channel, downloads by version, page views per day, top pages,
      top referrers, and top countries.
- [x] `/dashboard/` and its data endpoint refuse anyone who isn't Jake: a Basic-auth password
      prompt, and refusal when `DASHBOARD_PASSWORD` is unset. (Manual: open it in a private
      window.)
- [x] Rows older than 365 days are deleted daily.
- [x] The privacy page says what the site counts, dated, as its "Changes" section promises.
      (Drafted under `[COPY - Jake]`.)
- [ ] No `[COPY - Jake]` marker remains in shipped copy.

## Design
- **Storage:** Netlify Database (managed Postgres) through `@netlify/database` and Drizzle.
  `db/schema.ts` defines two tables: `downloads (id, at, version, channel, country)` and
  `page_views (id, at, path, referrer_host, country)`. Migrations are generated at deploy.
  Blobs was the alternative, but the dashboard's work is grouping and counting by day, which is
  a query in Postgres and hand-rolled aggregation in Blobs.
- **Counting:** one edge function, `netlify/edge-functions/count.ts`, mapped to `/downloads/*`
  and the four page paths. It calls `context.next()` for the response and, only for a 200 (or a
  206 starting at byte 0), hands the row to `POST /api/count` inside `context.waitUntil`. That
  keeps recording off the response path, and a failed write is swallowed. `onError: "bypass"`
  serves the file even if the edge function itself throws. Country comes from `context.geo`.
  Referrer is cut down to its host, dropping the site's own. The user-agent is read to decide
  channel and bot-ness and then thrown away. Page views also skip curl, wget and other HTTP
  libraries; downloads don't, since someone may really fetch the zip that way.
- **Why the hop to a serverless function:** `@netlify/database` pulls in `pg` and `ws`, which
  aren't safe to assume in the Deno edge runtime. `netlify/functions/count.mts` does the insert.
  It's public, as the zip URLs are, so it accepts only the shapes the edge function sends:
  version `N.N[.N]`, channel `brew|browser`, one of the four paths, a two-letter country and a
  hostname. A forged request can add a count, as fetching the zip in a loop could, but it can't
  put arbitrary text in front of the dashboard, and the dashboard sets text with `textContent`
  regardless.
- **Dashboard:** `site/dashboard/index.html` (static, noindex, self-contained rather than on the
  marketing stylesheets), plus `netlify/functions/stats.mts` at `/api/stats?range=30` returning
  the aggregates as JSON. Days are Salt Lake City days. Charts are inline SVG, no chart
  library: stacked daily columns for downloads (Homebrew/website), daily columns for page views
  (a separate chart, never a second axis), bar lists for versions, pages and referrers, a
  countries table, and every day as a table behind a disclosure. Hover and arrow keys read a
  day's numbers. Light and dark both use validated colours.
- **Access:** HTTP Basic auth against `DASHBOARD_PASSWORD`, one check in `netlify/lib/dashboard-auth.ts`
  used by the edge function `dashboard-auth.ts` on `/dashboard` and by the stats function itself.
  If the variable is unset, both refuse everyone (503) rather than opening.
- **Retention:** the daily scheduled function also deletes `downloads` and `page_views` rows
  older than 365 days.
- **Build:** the site still has no build command, and `site/` is still published as-is. A
  `package.json` brings in `@netlify/database` and `drizzle-orm@beta` (and `drizzle-kit@beta` to
  generate migrations). Netlify bundles the functions and applies
  `netlify/database/migrations` on deploy. `node_modules/` and `.netlify/` are ignored.
- **check-tap:** its `curl` for the zip gains `-A 'oncue-check-tap'`.

## Gates
- [ ] `scripts/check` passes (it doesn't touch the site, but the rule is the rule)
- [ ] The site still works through `scripts/site` with the functions absent (the local server
      doesn't run them, and a missing dashboard shouldn't break the pages)
- [ ] A deploy preview counts a browser download and a `brew fetch` correctly
- [ ] `DASHBOARD_PASSWORD` set in Netlify before merging (until then the dashboard is locked)

> Any user-facing string Claude proposes carries `[COPY - Jake]` until Jake rewrites or edits it
> and removes the marker himself. In a spec, describe what the copy must convey.

## Tasks
- [x] `package.json`, `db/schema.ts`, first migration
- [x] Edge function that counts downloads and page views, and `/api/count`
- [x] Stats function and access check
- [x] Daily scheduled function: 365-day pruning
- [x] `site/dashboard/`
- [x] `scripts/check-tap` user-agent
- [x] Privacy page paragraph, marked `[COPY - Jake]`
- [x] Jake: set `DASHBOARD_PASSWORD` in Netlify (Site configuration → Environment variables,
      scopes Functions and Edge Functions), then open `/dashboard/`

## Verification
2026-09-25, in the Netlify agent environment (Linux, no Xcode):
- `netlify dev`: pages and zips served unchanged (200, a missing zip 404). The edge function
  handed `/api/count` exactly the expected rows: brew and browser downloads with version and
  country, `/help/` with `news.ycombinator.com`, `/privacy/index.html` as `/privacy/`, and home
  with a browser user-agent. Nothing for Googlebot, `oncue-check-tap`, or home fetched by plain
  curl. The local static server ignores `Range`, so the resume case (206) is still to see on a
  deploy.
- Dashboard auth under `netlify dev`: 401 with no password or the wrong one on `/dashboard`,
  `/dashboard/` and `/dashboard/index.html`; 200 with it, sent `no-store` and `noindex`. With
  the variable unset: 503. `/api/stats` without the password: 401.
- The preview database branch doesn't exist until the first deploy, so the SQL was run against
  PGlite with the generated migration applied, through the real `count`, `stats` and `prune`
  handlers. Valid rows 204, forged path and version 400. The 7-day and all-time windows,
  zero-filled days, version order, referrers and countries were right, and prune removed the
  400-day-old row only. This caught a real bug: the bound time zone made Postgres reject the
  GROUP BY. It's now a literal.
- Dashboard rendered in headless Chromium with sample data, light and dark at 1200px and a
  phone at 390px. No script errors, the tooltip reads the hovered day, and the empty states
  show. Series colours pass the palette validator in both modes.
- `scripts/check` not run: no Xcode here, and nothing in the app changed. `scripts/ship-check`
  fails on the privacy paragraph's markers, as it should until Jake rewrites it.
- Still to do on the first deploy: a browser download, a `brew fetch`, and `scripts/check-tap`,
  then the dashboard.
- 2026-09-25 16:12 MDT, on the deploy of `3dd13cf`: `/dashboard/` answers 401 with the
  `OnCue dashboard` realm (so the password is set and the guard runs); home, help, changelog,
  privacy and a HEAD of the 4.14 zip answer 200. All fetched with the `oncue-check-tap`
  user-agent, so none of it counted. A browser download and a `brew fetch` against the live
  counter are Jake's to make when he wants the first rows to be real.

## Decisions (2026-09-25, Jake)
1. **Counting on the public site is fine.** Only the app collects nothing. The privacy page gets a
   dated paragraph saying so, marked `[COPY - Jake]`.
2. **Page views and downloads,** both.
3. **Access: HTTP Basic auth.** The browser asks for a password, which is checked against an
   environment variable (`DASHBOARD_PASSWORD`) set in the Netlify UI. It needs no login page and
   no account system. Netlify Identity is Netlify's hosted user-account service, with sign-up,
   login, email confirmation, and a JavaScript widget on the page. That's more moving parts than
   one person reading one page needs.
4. **Retention: raw rows for a year.** A daily scheduled function deletes rows older than 365
   days.
5. **Backfill: none.** Nothing holds per-file history to import. The Netlify site was created on
   2026-09-20 and Netlify Analytics was never on. The nearest thing, the tap's GitHub clone
   counts (14 days, a signal of brew users rather than downloads), was offered and declined.
   Counting starts at deploy, and the dashboard says "Counting since" the first row.
6. **Approved** 2026-09-25.

## Open questions
None.

## Closure
Live on 2026-09-25 (16:12 MDT) with the push of `3dd13cf`. Site only, so no app release
carries it; the privacy page's "since 25 September 2026" holds from that push.
