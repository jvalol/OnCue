// Counts zip downloads and page views on the public site (spec 0052). The app itself never
// reports anything; this only notices requests the site is already serving.
//
// Nothing here can fail or slow a request: the row is handed to /api/count after the response
// has gone, and any error is dropped. The user-agent is read to tell brew from a browser and to
// skip bots, then thrown away; the IP address is never read.
import type { Config, Context } from "@netlify/edge-functions";

// The old hostname only redirects here (see site/_redirects); the redirected request is the one
// to count.
const OLD_HOST = "oncue-web.netlify.app";

// scripts/check-tap fetches the zip the way brew does, and it runs after every release.
const CHECK_TAP = /oncue-check-tap/i;
// The fediverse fetches a linked page once per instance to build its preview card, which on
// 2026-10-16 counted as two hundred readers in a day; the fetchers name their software, not a bot.
const BOT = /bot|crawl|spider|slurp|facebookexternalhit|embedly|preview|monitor|uptime|headless|lighthouse|mastodon|misskey|akkoma|pleroma|friendica|lemmy|calckey|firefish|sharkey|iceshrimp/i;
// Fine for a download (someone may fetch the zip with curl), never a reader of a page.
const TOOL = /^(curl|wget|python|go-http-client|node|axios|okhttp|java)/i;

const PAGES: Record<string, string> = {
  "/": "/",
  "/index.html": "/",
  "/help/": "/help/",
  "/help/index.html": "/help/",
  "/changelog/": "/changelog/",
  "/changelog/index.html": "/changelog/",
  "/privacy/": "/privacy/",
  "/privacy/index.html": "/privacy/",
  "/check/": "/check/",
  "/check/index.html": "/check/",
  "/mac-security-camera/": "/mac-security-camera/",
  "/mac-security-camera/index.html": "/mac-security-camera/",
};

const ZIP = /^\/downloads\/OnCue-(\d+(?:\.\d+){1,3})\.zip$/;

export default async (req: Request, context: Context) => {
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.hostname === OLD_HOST) return;

  const agent = req.headers.get("user-agent") ?? "";
  if (CHECK_TAP.test(agent) || BOT.test(agent)) return;

  const zip = ZIP.exec(url.pathname);
  const page = PAGES[url.pathname];
  if (!zip && !page) return;
  if (page && TOOL.test(agent)) return;

  const response = await context.next();
  if (!firstByteServed(req, response)) return response;

  const country = context.geo?.country?.code ?? null;
  const row = zip
    ? { kind: "download", version: zip[1], channel: /homebrew/i.test(agent) ? "brew" : "browser", country }
    : { kind: "page", path: page, referrerHost: referrerHost(req, url), country };

  context.waitUntil(
    fetch(new URL("/api/count", url), {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(row),
    }).catch(() => {}),
  );
  return response;
};

// A resumed download (a Range request that doesn't start at byte 0) is the same download again.
function firstByteServed(req: Request, response: Response): boolean {
  if (response.status === 200) return true;
  if (response.status !== 206) return false;
  return /^bytes=0-/.test(req.headers.get("range") ?? "");
}

function referrerHost(req: Request, url: URL): string | null {
  const referrer = req.headers.get("referer");
  if (!referrer) return null;
  try {
    const host = new URL(referrer).hostname.toLowerCase();
    if (!host || host === url.hostname || host === OLD_HOST) return null;
    return host.replace(/^www\./, "");
  } catch {
    return null;
  }
}

export const config: Config = {
  path: ["/", "/index.html", "/help/*", "/changelog/*", "/privacy/*", "/check/*", "/mac-security-camera/*", "/downloads/*"],
  onError: "bypass",
};
