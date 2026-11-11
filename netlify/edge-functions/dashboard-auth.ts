// Guards the dashboard page (spec 0052). The stats function checks the same password itself.
import type { Config, Context } from "@netlify/edge-functions";
import { authFailure, checkDashboardAuth } from "../lib/dashboard-auth.ts";

export default async (req: Request, context: Context) => {
  const result = checkDashboardAuth(req, Netlify.env.get("DASHBOARD_PASSWORD"));
  if (result !== "ok") return authFailure(result);
  const response = await context.next();
  response.headers.set("cache-control", "no-store");
  response.headers.set("x-robots-tag", "noindex");
  return response;
};

export const config: Config = {
  path: ["/dashboard", "/dashboard/*"],
};
