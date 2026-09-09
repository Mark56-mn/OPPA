/** Run a command with DATABASE_URL injected from .env (never printed). */
import { readFileSync, existsSync } from "node:fs";
import { spawnSync } from "node:child_process";

const text = existsSync(".env") ? readFileSync(".env", "utf8") : "";
let url = process.env.DATABASE_URL || "";
if (!url) {
  const m = text.match(/^DATABASE_URL\s*=\s*(.+)\s*$/m);
  if (m) url = m[1].replace(/^["']|["']$/g, "");
}
if (!url) {
  console.error("db-run: no DATABASE_URL available");
  process.exit(2);
}
if (url.includes(":6543/")) {
  url = url.replace(":6543/", ":5432/");
}
const [cmd, ...args] = process.argv.slice(2);
if (!cmd) {
  console.error("db-run: usage: node scripts/db-run.mjs <command> [args...]");
  process.exit(2);
}
const r = spawnSync(cmd, args, {
  stdio: "inherit",
  env: { ...process.env, DATABASE_URL: url },
});
process.exit(r.status ?? 1);
