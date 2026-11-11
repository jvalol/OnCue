// Stores one row handed over by the count edge function (spec 0052).
//
// This endpoint is public, as the zip URLs are, so everything is checked against the shapes the
// edge function sends. A made-up request can add a count, as fetching the zip in a loop could,
// but it can't put arbitrary text into the dashboard.
import type { Config } from "@netlify/functions";
import { db } from "../../db/index.js";
import { downloads, pageViews } from "../../db/schema.js";

const VERSION = /^\d+(?:\.\d+){1,3}$/;
const PAGES = new Set(["/", "/help/", "/changelog/", "/privacy/", "/check/", "/mac-security-camera/"]);
const COUNTRY = /^[A-Z]{2}$/;
const HOST = /^[a-z0-9.-]{1,253}$/;

export default async (req: Request) => {
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return new Response(null, { status: 400 });
  }
  const country = typeof body.country === "string" && COUNTRY.test(body.country) ? body.country : null;

  if (body.kind === "download") {
    if (typeof body.version !== "string" || !VERSION.test(body.version)) return new Response(null, { status: 400 });
    if (body.channel !== "brew" && body.channel !== "browser") return new Response(null, { status: 400 });
    await db.insert(downloads).values({ version: body.version, channel: body.channel, country });
    return new Response(null, { status: 204 });
  }

  if (body.kind === "page") {
    if (typeof body.path !== "string" || !PAGES.has(body.path)) return new Response(null, { status: 400 });
    const referrerHost =
      typeof body.referrerHost === "string" && HOST.test(body.referrerHost) ? body.referrerHost : null;
    await db.insert(pageViews).values({ path: body.path, referrerHost, country });
    return new Response(null, { status: 204 });
  }

  return new Response(null, { status: 400 });
};

export const config: Config = {
  path: "/api/count",
  method: "POST",
};
