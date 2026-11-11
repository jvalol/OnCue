// The dashboard's lock (spec 0052): HTTP Basic auth against DASHBOARD_PASSWORD, set in the
// Netlify UI. The user name is ignored. With no password set, nobody gets in.
//
// Shared by the edge function that guards /dashboard/ and the stats function, so both read
// the variable the same way. Kept free of Node and Deno specifics so either runtime can use it.

export type AuthResult = "ok" | "unconfigured" | "denied";

export function checkDashboardAuth(req: Request, password: string | undefined): AuthResult {
  if (!password) return "unconfigured";
  const header = req.headers.get("authorization") ?? "";
  const match = /^Basic\s+(.+)$/i.exec(header);
  if (!match) return "denied";
  let decoded: string;
  try {
    decoded = atob(match[1]);
  } catch {
    return "denied";
  }
  const given = decoded.slice(decoded.indexOf(":") + 1);
  return sameString(given, password) ? "ok" : "denied";
}

export function authFailure(result: Exclude<AuthResult, "ok">): Response {
  if (result === "unconfigured") {
    return new Response("The dashboard is locked until DASHBOARD_PASSWORD is set in Netlify.\n", {
      status: 503,
      headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" },
    });
  }
  return new Response("Password required.\n", {
    status: 401,
    headers: {
      "www-authenticate": 'Basic realm="OnCue dashboard", charset="UTF-8"',
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

// Compares every character so the time taken doesn't say how much of a guess was right.
function sameString(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < y.length; i++) diff |= (x[i] ?? 0) ^ y[i];
  return diff === 0;
}
