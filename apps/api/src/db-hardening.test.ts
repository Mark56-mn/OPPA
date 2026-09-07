/**
 * DB-hardening regression tests (migration 0019).
 *
 * Run only when DATABASE_URL is configured — these are REAL Postgres
 * concurrency/integrity tests, not fakes:
 *
 *   DATABASE_URL=postgres://... bun test src/db-hardening.test.ts
 *
 * They apply migrations 0016 + 0018 + 0019 to the configured database, prove
 * the invariants reject invalid states under concurrency, and clean up after
 * themselves. Never run against a database you cannot afford to touch.
 */
import assert from "node:assert/strict";
import test, { after, before } from "node:test";
import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import pg from "pg";

const connectionString = process.env.DATABASE_URL;
const skip = connectionString
  ? false
  : "DATABASE_URL is not configured; DB-hardening integration tests skipped";

const migrations = [
  "0016_business.sql",
  "0018_reports_calls.sql",
  "0019_db_hardening.sql"
];

let pool: pg.Pool;
let userA: string;
let userB: string;
let businessId: string;
let productId: string;
let conversationId: string;

async function applyMigrations() {
  const base = new URL("../../../database/migrations/", import.meta.url);
  await pool.query(`create table if not exists public.schema_migrations (
    name text primary key, applied_at timestamptz not null default now())`);
  for (const file of migrations) {
    const sql = await readFile(new URL(file, base), "utf8");
    try {
      await pool.query(sql);
    } catch (e: any) {
      // Idempotent-safe migrations may conflict on concurrent CI runs only.
      if (!String(e.message).includes("already exists")) throw e;
    }
  }
}

before(async () => {
  if (!connectionString) return;
  pool = new pg.Pool({ connectionString, max: 10 });
  await applyMigrations();

  const suffix = randomUUID().replaceAll("-", "").slice(0, 10);
  userA = (await pool.query("insert into public.oppa_users(phone_e164) values($1) returning id", [`+1999${suffix}a`])).rows[0].id;
  userB = (await pool.query("insert into public.oppa_users(phone_e164) values($1) returning id", [`+1999${suffix}b`])).rows[0].id;
  await pool.query("insert into public.oppa_wallets(user_id,currency) values($1,'NGN'),($2,'NGN') on conflict do nothing", [userA, userB]);

  businessId = (await pool.query(
    "insert into public.oppa_businesses(owner_user_id,name) values($1,'Hardening Test Store') returning id",
    [userA]
  )).rows[0].id;
  productId = (await pool.query(
    "insert into public.oppa_business_products(business_id,name,price_minor) values($1,'Widget',1000) returning id",
    [businessId]
  )).rows[0].id;

  conversationId = (await pool.query(
    "insert into public.oppa_conversations(kind) values('direct') returning id"
  )).rows[0].id;
  await pool.query(
    "insert into public.oppa_conversation_members(conversation_id,user_id) values($1,$2),($1,$3)",
    [conversationId, userA, userB]
  );
});

after(async () => {
  if (!connectionString) return;
  // Remove only the rows this test created (children cascade).
  await pool.query("delete from public.oppa_calls where conversation_id=$1", [conversationId]);
  await pool.query("delete from public.oppa_conversations where id=$1", [conversationId]);
  await pool.query("delete from public.oppa_business_order_items where order_id in (select id from public.oppa_business_orders where business_id=$1)", [businessId]);
  await pool.query("delete from public.oppa_business_orders where business_id=$1", [businessId]);
  await pool.query("delete from public.oppa_business_products where id=$1", [productId]);
  await pool.query("delete from public.oppa_businesses where id=$1", [businessId]);
  await pool.query("delete from public.oppa_wallets where user_id in ($1,$2)", [userA, userB]);
  await pool.query("delete from public.oppa_users where id in ($1,$2)", [userA, userB]);
  await pool.end();
});

test("two concurrent startCall transactions cannot both leave a ringing call", { skip }, async () => {
  const start = async () => {
    const c = await pool.connect();
    try {
      await c.query("begin");
      // Mirror the service's insert path: INSERT only (the unique partial
      // index is the arbiter — no pre-check, so the race is real).
      await c.query(
        `insert into public.oppa_calls(conversation_id, caller_user_id, kind)
         values ($1,$2,'audio')`,
        [conversationId, userA]
      );
      await c.query("commit");
      return "ok";
    } catch (e: any) {
      await c.query("rollback").catch(() => {});
      return e.code ?? e.message;
    } finally {
      c.release();
    }
  };
  const [r1, r2] = await Promise.all([start(), start()]);
  const wins = [r1, r2].filter((r) => r === "ok").length;
  assert.equal(wins, 1, "exactly one of two concurrent calls may start");
  const loser = r1 === "ok" ? r2 : r1;
  assert.match(String(loser), /23505|duplicate key|unique constraint/,
    "the loser fails with a unique violation");

  // Cleanup the winner so later tests start clean, and prove ended calls
  // never block new ones.
  await pool.query(
    "update public.oppa_calls set status='ended', end_reason='cancelled', ended_at=now() where conversation_id=$1 and status='ringing'",
    [conversationId]
  );
  const again = await pool.query(
    `insert into public.oppa_calls(conversation_id, caller_user_id, kind) values ($1,$2,'audio') returning id`,
    [conversationId, userA]
  );
  assert.ok(again.rows[0].id, "a new call may start once the previous one ended");
  await pool.query("delete from public.oppa_calls where conversation_id=$1", [conversationId]);
});

test("an order item cannot reference another business's product", { skip }, async () => {
  // Business B (owned by userB) with its own product.
  const bizB = (await pool.query(
    "insert into public.oppa_businesses(owner_user_id,name) values($1,'Other Store') returning id",
    [userB]
  )).rows[0].id;
  const prodB = (await pool.query(
    "insert into public.oppa_business_products(business_id,name,price_minor) values($1,'Other Widget',500) returning id",
    [bizB]
  )).rows[0].id;

  const order = (await pool.query(
    "insert into public.oppa_business_orders(business_id,customer_user_id,amount_minor) values($1,$2,1000) returning id",
    [businessId, userB]
  )).rows[0].id;

  await assert.rejects(
    () => pool.query(
      "insert into public.oppa_business_order_items(order_id,product_id,quantity,unit_price_minor) values($1,$2,1,1000)",
      [order, prodB]
    ),
    (e: any) => /23503|foreign key|same_business/i.test(String(e.message) + String(e.code ?? "")),
    "cross-business item must be rejected by the composite FK"
  );

  // Same-business items still work.
  await pool.query(
    "insert into public.oppa_business_order_items(order_id,product_id,quantity,unit_price_minor) values($1,$2,1,1000)",
    [order, productId]
  );
  const n = await pool.query("select count(*)::int as n from public.oppa_business_order_items where order_id=$1", [order]);
  assert.equal(n.rows[0].n, 1);

  await pool.query("delete from public.oppa_business_order_items where order_id=$1", [order]);
  await pool.query("delete from public.oppa_business_orders where id=$1", [order]);
  await pool.query("delete from public.oppa_business_products where id=$1", [prodB]);
  await pool.query("delete from public.oppa_businesses where id=$1", [bizB]);
});

test("Data API roles have no privileges on OPPA tables (deny-all RLS)", { skip }, async () => {
  const tables = await pool.query(
    `select tablename from pg_tables where schemaname='public' and tablename like 'oppa_%'`
  );
  assert.ok(tables.rowCount && tables.rowCount > 10, "expected the full OPPA table set");
  const rls = await pool.query(
    `select c.relname, c.relrowsecurity as rls
     from pg_class c join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and c.relname like 'oppa_%' and c.relkind='r'`
  );
  for (const row of rls.rows) {
    assert.equal(row.rls, true, `${row.relname} must have RLS enabled`);
  }
  // No policies at all: PostgREST sees zero rows, privileged backend bypasses RLS.
  const policies = await pool.query(
    `select count(*)::int as n from pg_policies where schemaname='public' and tablename like 'oppa_%'`
  );
  assert.equal(policies.rows[0].n, 0,
    "no RLS policies should exist on oppa_% tables (deny-all, privileged-backend architecture)");
});
