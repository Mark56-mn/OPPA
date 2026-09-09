/**
 * Idempotent migration runner.
 *
 * Usage: DATABASE_URL=... npx tsx src/scripts/migrate.ts
 *
 * Applies database/migrations/*.sql in lexicographic order exactly once,
 * tracked in public.schema_migrations. Each migration runs inside a
 * transaction (Postgres DDL is transactional), so a failed migration leaves
 * no partial state and is retried on the next run.
 */
import { readdir, readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Pool } from "pg";

const here = dirname(fileURLToPath(import.meta.url));
const migrationsDir = join(here, "../../../../database/migrations");

async function main() {
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) {
    console.error("migrate: DATABASE_URL is not configured; nothing to do");
    process.exit(1);
  }
  const pool = new Pool({
    connectionString,
    max: 1,
    ssl: process.env.DB_SSL === "false" ? false : { rejectUnauthorized: false }
  });
  try {
    await pool.query(`
      create table if not exists public.schema_migrations (
        name text primary key,
        applied_at timestamptz not null default now()
      )`);
    const files = (await readdir(migrationsDir)).filter(f => f.endsWith(".sql")).sort();
    if (files.length === 0) {
      console.log("migrate: no migration files found");
      return;
    }
    const applied = new Set(
      (await pool.query<{ name: string }>("select name from public.schema_migrations")).rows.map(r => r.name)
    );
    let ran = 0;
    for (const file of files) {
      if (applied.has(file)) continue;
      const sql = await readFile(join(migrationsDir, file), "utf8");
      const client = await pool.connect();
      try {
        await client.query("begin");
        await client.query(sql);
        await client.query("insert into public.schema_migrations(name) values ($1)", [file]);
        await client.query("commit");
        ran += 1;
        console.log(`migrate: applied ${file}`);
      } catch (e) {
        await client.query("rollback").catch(() => {});
        console.error(`migrate: FAILED ${file}:`, e instanceof Error ? e.message : e);
        process.exitCode = 1;
        break; // Stop at first failure; ordering is significant.
      } finally {
        client.release();
      }
    }
    console.log(`migrate: ${ran} applied, ${applied.size} already current`);
  } finally {
    await pool.end();
  }
}

main().catch(e => {
  console.error("migrate:", e instanceof Error ? e.message : e);
  process.exit(1);
});
