import assert from "node:assert/strict";
import test, { after, before } from "node:test";
import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import pg from "pg";
import { PostgresSecurityRepository } from "./postgres-security-repository.js";
import { hashIntent } from "./intent-binding.js";

const connectionString = process.env.DATABASE_URL;
const skip = connectionString ? false : "DATABASE_URL is not configured; integration tests skipped";

const migrations = [
  "0001_oppa_foundation.sql",
  "0011_security_core.sql",
  "0012_security_intent_binding.sql"
];

let pool: pg.Pool;
let userId: string;
let deviceId: string;

before(async () => {
  if (!connectionString) return;
  pool = new pg.Pool({ connectionString, max: 10 });
  const base = new URL("../../../../../database/migrations/", import.meta.url);
  for (const file of migrations) {
    const sql = await readFile(new URL(file, base), "utf8");
    await pool.query(sql);
  }
  const user = await pool.query("insert into public.oppa_users(phone_e164) values($1) returning id", [`+1999${randomUUID().replaceAll("-", "").slice(0, 11)}`]);
  userId = user.rows[0].id;
  const device = await pool.query("insert into public.oppa_devices(user_id, device_public_key, platform) values($1,$2,'android') returning id", [userId, "test-public-key"]);
  deviceId = device.rows[0].id;
});

after(async () => {
  if (!connectionString) return;
  await pool.query("delete from public.oppa_step_up_challenges where user_id=$1", [userId]);
  await pool.query("delete from public.oppa_devices where id=$1", [deviceId]);
  await pool.query("delete from public.oppa_users where id=$1", [userId]);
  await pool.end();
});

test("concurrent consumption consumes the challenge exactly once", { skip }, async () => {
  const repo = new PostgresSecurityRepository();
  const challenge = randomUUID();
  await repo.createChallenge({ userId, deviceId, purpose: "wallet_transfer", challengeHash: "hash-" + challenge, expiresAt: new Date(Date.now() + 60_000), maxAttempts: 5 });
  const record = await repo.findActiveChallenge(userId, "wallet_transfer");
  assert.ok(record);
  const results = await Promise.all([repo.consumeChallenge(record.id, new Date()), repo.consumeChallenge(record.id, new Date())]);
  assert.equal(results.filter(Boolean).length, 1);
  assert.equal(await repo.findActiveChallenge(userId, "wallet_transfer"), null);
});

test("concurrent challenge creation leaves exactly one active challenge", { skip }, async () => {
  const repo = new PostgresSecurityRepository();
  const outcomes = await Promise.allSettled([
    repo.createChallenge({ userId, deviceId, purpose: "payment_reversal", challengeHash: "hash-a-" + randomUUID(), expiresAt: new Date(Date.now() + 60_000), maxAttempts: 5 }),
    repo.createChallenge({ userId, deviceId, purpose: "payment_reversal", challengeHash: "hash-b-" + randomUUID(), expiresAt: new Date(Date.now() + 60_000), maxAttempts: 5 })
  ]);
  const fulfilled = outcomes.filter((o) => o.status === "fulfilled").length;
  const conflicted = outcomes.filter((o) => o.status === "rejected" && (o.reason as Error).message === "STEP_UP_CHALLENGE_CONFLICT").length;
  assert.equal(fulfilled, 1);
  assert.equal(conflicted, 1);
  const remaining = await pool.query("select count(*)::int as n from public.oppa_step_up_challenges where user_id=$1 and purpose='payment_reversal' and consumed_at is null", [userId]);
  assert.equal(remaining.rows[0].n, 1);
});

test("an expired challenge is never consumable", { skip }, async () => {
  const repo = new PostgresSecurityRepository();
  await repo.createChallenge({ userId, deviceId, purpose: "security_change", challengeHash: "hash-expired-" + randomUUID(), expiresAt: new Date(Date.now() - 60_000), maxAttempts: 5 });
  const record = await repo.findActiveChallenge(userId, "security_change");
  assert.equal(record, null);
});

test("intent hash round-trips with the active challenge", { skip }, async () => {
  const repo = new PostgresSecurityRepository();
  const intent = { toUserId: "u-other", amountMinor: 50000, currency: "NGN", reference: "ref-1" };
  const intentHash = hashIntent(intent);
  await repo.createChallenge({ userId, deviceId, purpose: "account_recovery", challengeHash: "hash-intent-" + randomUUID(), expiresAt: new Date(Date.now() + 60_000), maxAttempts: 5, intentHash });
  const record = await repo.findActiveChallenge(userId, "account_recovery");
  assert.ok(record);
  assert.equal(record.intentHash, intentHash);
});

test("concurrent attempt increments are applied atomically", { skip }, async () => {
  const repo = new PostgresSecurityRepository();
  await repo.createChallenge({ userId, deviceId, purpose: "wallet_transfer", challengeHash: "hash-attempts-" + randomUUID(), expiresAt: new Date(Date.now() + 60_000), maxAttempts: 5 });
  const record = await repo.findActiveChallenge(userId, "wallet_transfer");
  assert.ok(record);
  await Promise.all([repo.incrementChallengeAttempt(record.id), repo.incrementChallengeAttempt(record.id)]);
  const row = await pool.query("select attempts from public.oppa_step_up_challenges where id=$1", [record.id]);
  assert.equal(row.rows[0].attempts, 2);
});