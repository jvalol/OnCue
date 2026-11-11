CREATE TABLE "downloads" (
	"id" serial PRIMARY KEY,
	"at" timestamp with time zone DEFAULT now() NOT NULL,
	"version" text NOT NULL,
	"channel" text NOT NULL,
	"country" text
);
--> statement-breakpoint
CREATE TABLE "page_views" (
	"id" serial PRIMARY KEY,
	"at" timestamp with time zone DEFAULT now() NOT NULL,
	"path" text NOT NULL,
	"referrer_host" text,
	"country" text
);
--> statement-breakpoint
CREATE INDEX "downloads_at_idx" ON "downloads" ("at");--> statement-breakpoint
CREATE INDEX "page_views_at_idx" ON "page_views" ("at");