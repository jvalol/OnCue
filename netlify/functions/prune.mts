// Keeps a year of raw rows (spec 0052). Runs daily on the published deploy only.
import type { Config } from "@netlify/functions";
import { lt, sql } from "drizzle-orm";
import { db } from "../../db/index.js";
import { downloads, pageViews } from "../../db/schema.js";

export default async () => {
  const cutoff = sql`now() - interval '365 days'`;
  await db.delete(downloads).where(lt(downloads.at, cutoff));
  await db.delete(pageViews).where(lt(pageViews.at, cutoff));
};

export const config: Config = {
  schedule: "@daily",
};
