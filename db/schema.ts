// What the public site counts (spec 0052). Counts, not visitors: no IP address, no user-agent
// string, nothing that ties two rows to one person. Rows older than a year are pruned daily.
import { index, pgTable, serial, text, timestamp } from "drizzle-orm/pg-core";

// One row per zip download that got its first byte served.
export const downloads = pgTable(
  "downloads",
  {
    id: serial().primaryKey(),
    at: timestamp("at", { withTimezone: true }).notNull().defaultNow(),
    version: text().notNull(),
    // "brew" when Homebrew fetched it, "browser" for everything else.
    channel: text().notNull(),
    // ISO 3166 code from Netlify's geolocation, null when it has none.
    country: text(),
  },
  (t) => [index("downloads_at_idx").on(t.at)],
);

// One row per view of a site page.
export const pageViews = pgTable(
  "page_views",
  {
    id: serial().primaryKey(),
    at: timestamp("at", { withTimezone: true }).notNull().defaultNow(),
    path: text().notNull(),
    // Host only, never the full referring URL; null for direct visits and the site's own links.
    referrerHost: text("referrer_host"),
    country: text(),
  },
  (t) => [index("page_views_at_idx").on(t.at)],
);
