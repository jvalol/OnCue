// Aggregates for the dashboard (spec 0052): GET /api/stats?range=7|30|90|all.
//
// Days are Salt Lake City days, since that's where the person reading this is.
import type { Config } from "@netlify/functions";
import { and, count, desc, isNotNull, min, sql, type SQL } from "drizzle-orm";
import { db } from "../../db/index.js";
import { downloads, pageViews } from "../../db/schema.js";
import { authFailure, checkDashboardAuth } from "../lib/dashboard-auth.js";

const ZONE = "America/Denver";
// Written into the SQL rather than bound: Postgres only matches a GROUP BY expression to the
// selected one when they're identical, and two bound parameters never are.
const ZONE_SQL = sql.raw(`'${ZONE}'`);
const RANGES: Record<string, number | null> = { "7": 7, "30": 30, "90": 90, all: null };

export default async (req: Request) => {
  const auth = checkDashboardAuth(req, Netlify.env.get("DASHBOARD_PASSWORD"));
  if (auth !== "ok") return authFailure(auth);

  const key = new URL(req.url).searchParams.get("range") ?? "30";
  if (!(key in RANGES)) return new Response("range must be 7, 30, 90 or all\n", { status: 400 });
  const days = RANGES[key];

  // Windows are whole local days, today included.
  const today = localDay(new Date());
  const windowStart = days === null ? null : addDays(today, -(days - 1));
  const inWindow = (at: SQL | typeof downloads.at | typeof pageViews.at) =>
    windowStart ? sql`(${at} at time zone ${ZONE_SQL})::date >= ${windowStart}::date` : undefined;
  const inDownloads = inWindow(downloads.at);
  const inViews = inWindow(pageViews.at);

  const downloadDay = sql<string>`to_char(${downloads.at} at time zone ${ZONE_SQL}, 'YYYY-MM-DD')`;
  const viewDay = sql<string>`to_char(${pageViews.at} at time zone ${ZONE_SQL}, 'YYYY-MM-DD')`;
  const n = () => sql<number>`count(*)::int`;

  const [downloadsByDay, viewsByDay, versions, pages, referrers, downloadCountries, viewCountries, first] =
    await Promise.all([
      db
        .select({ day: downloadDay, channel: downloads.channel, n: n() })
        .from(downloads)
        .where(inDownloads)
        .groupBy(downloadDay, downloads.channel),
      db.select({ day: viewDay, n: n() }).from(pageViews).where(inViews).groupBy(viewDay),
      db
        .select({ version: downloads.version, n: n() })
        .from(downloads)
        .where(inDownloads)
        .groupBy(downloads.version),
      db
        .select({ path: pageViews.path, n: n() })
        .from(pageViews)
        .where(inViews)
        .groupBy(pageViews.path)
        .orderBy(desc(count())),
      db
        .select({ host: pageViews.referrerHost, n: n() })
        .from(pageViews)
        .where(and(inViews, isNotNull(pageViews.referrerHost)))
        .groupBy(pageViews.referrerHost)
        .orderBy(desc(count()))
        .limit(10),
      db
        .select({ country: downloads.country, n: n() })
        .from(downloads)
        .where(and(inDownloads, isNotNull(downloads.country)))
        .groupBy(downloads.country),
      db
        .select({ country: pageViews.country, n: n() })
        .from(pageViews)
        .where(and(inViews, isNotNull(pageViews.country)))
        .groupBy(pageViews.country),
      Promise.all([
        db.select({ at: min(downloads.at) }).from(downloads),
        db.select({ at: min(pageViews.at) }).from(pageViews),
      ]),
    ]);

  // Every day in the window gets a row, zeros included, so the chart's gaps are real ones.
  const firstCounted = [first[0][0]?.at, first[1][0]?.at]
    .filter((at): at is Date => at != null)
    .map((at) => localDay(new Date(at)))
    .sort()[0];
  const from = windowStart ?? firstCounted ?? today;
  const daily = new Map<string, { day: string; brew: number; browser: number; views: number }>();
  for (let day = from; day <= today; day = addDays(day, 1)) daily.set(day, { day, brew: 0, browser: 0, views: 0 });
  for (const row of downloadsByDay) {
    const entry = daily.get(row.day);
    if (entry && (row.channel === "brew" || row.channel === "browser")) entry[row.channel] += row.n;
  }
  for (const row of viewsByDay) {
    const entry = daily.get(row.day);
    if (entry) entry.views += row.n;
  }

  const countries = new Map<string, { country: string; downloads: number; views: number }>();
  const country = (code: string) =>
    countries.get(code) ?? countries.set(code, { country: code, downloads: 0, views: 0 }).get(code)!;
  for (const row of downloadCountries) if (row.country) country(row.country).downloads += row.n;
  for (const row of viewCountries) if (row.country) country(row.country).views += row.n;

  const dailyRows = [...daily.values()];
  const sum = (pick: (d: (typeof dailyRows)[number]) => number) => dailyRows.reduce((total, d) => total + pick(d), 0);

  return Response.json(
    {
      range: key,
      from,
      to: today,
      countingSince: firstCounted ?? null,
      totals: {
        downloads: sum((d) => d.brew + d.browser),
        brew: sum((d) => d.brew),
        browser: sum((d) => d.browser),
        views: sum((d) => d.views),
      },
      daily: dailyRows,
      versions: versions.sort((a, b) => compareVersions(b.version, a.version)),
      pages,
      referrers,
      countries: [...countries.values()]
        .sort((a, b) => b.downloads + b.views - (a.downloads + a.views))
        .slice(0, 12),
    },
    { headers: { "cache-control": "no-store" } },
  );
};

function localDay(date: Date): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: ZONE, year: "numeric", month: "2-digit", day: "2-digit" }).format(
    date,
  );
}

function addDays(day: string, n: number): string {
  const date = new Date(`${day}T12:00:00Z`);
  date.setUTCDate(date.getUTCDate() + n);
  return date.toISOString().slice(0, 10);
}

function compareVersions(a: string, b: string): number {
  const x = a.split(".").map(Number);
  const y = b.split(".").map(Number);
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const diff = (x[i] ?? 0) - (y[i] ?? 0);
    if (diff) return diff;
  }
  return 0;
}

export const config: Config = {
  path: "/api/stats",
  method: "GET",
};
