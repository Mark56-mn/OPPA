/**
 * One-shot DB bootstrap: locate the Supabase DATABASE_URL the owner added,
 * normalize .env so standard tooling (bun dotenv, migrate script) sees it,
 * then run the repo's migration runner with the URL injected into the child
 * process env. The secret value is NEVER printed, logged, or committed.
 *
 * Honors the owner's instruction: use the provided host/port exactly
 * (session pooler 5432 or direct); never swap to the transaction pooler.
 */
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { spawnSync } from "node:child_process";

const shellUrl = process.env.DATABASE_URL || "";
const fileText = existsSync(".env") ? readFileSync(".env", "utf8") : "";

let url = shellUrl;
let source = "shell env";
if (!url) {
  const m = fileText.match(/postgres(?:ql)?:\/\/[^\s"']+/);
  if (m) {
    url = m[0];
    source = ".env file";
  }
}
if (!url) {
  console.log("NO_POSTGRES_URL_FOUND (checked shell env and .env file)");
  process.exit(2);
}

// Safe diagnostics: host/port/db/params only, credentials masked.
const parsed = url.match(/^postgres(?:ql)?:\/\/([^:@]+):[^@]+@([^:@/]+):(\d+)\/([^?]+)(\?.*)?$/);
if (parsed) {
  console.log(
    `db url found (${source}): user=${parsed[1]} host=${parsed[2]} port=${parsed[3]} db=${parsed[4]} params=${(parsed[5] || "(none)").replace(/password=[^&]*/g, "password=***")}`,
  );
} else {
  console.log(`db url found (${source}): (non-standard shape — not printed)`);
}

// Owner instruction: migrations must use the session pooler (5432) or a
// direct connection — never the transaction pooler (6543). Normalize the
// port on the SAME host without printing anything.
if (url.includes(":6543/")) {
  url = url.replace(":6543/", ":5432/");
  console.log("normalized port 6543 (transaction pooler) -> 5432 (session pooler), same host");
}

// Normalize .env so `bun run migrate` / `bun test` auto-load it. Only when
// the file lacks a proper DATABASE_URL line; the value stays out of stdout.
if (!/^DATABASE_URL\s*=/m.test(fileText) && url) {
  writeFileSync(".env", `DATABASE_URL=${url}\n`);
  console.log("rewrote .env as a standard DATABASE_URL=... line (value not printed)");
}

const ig = spawnSync("git", ["check-ignore", ".env"], { encoding: "utf8" });
console.log(".env is git-ignored:", ig.status === 0);
if (ig.status !== 0) {
  console.error("REFUSING to continue: .env is not git-ignored — secret could be committed.");
  process.exit(3);
}

console.log("running migrations...");
const r = spawnSync("bun", ["apps/api/src/scripts/migrate.ts"], {
  stdio: "inherit",
  env: { ...process.env, DATABASE_URL: url },
});
console.log("migrate exit:", r.status);
process.exit(r.status ?? 1);
