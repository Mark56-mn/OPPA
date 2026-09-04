import assert from "node:assert/strict";
import test from "node:test";

/**
 * Regression coverage for transactional step-up challenge creation: the
 * consume-then-insert pair in PostgresSecurityProofRepository.createChallenge
 * must run in ONE transaction, so a failed insert rolls back the consume and
 * the user is never left without a usable challenge (step-up self-denial).
 *
 * This test verifies the SQL call sequence through a fake pg client. The
 * production query text is mirrored here; if the repository's SQL changes in
 * a way that breaks the invariant (e.g. consume outside the transaction),
 * this test fails and the invariant must be re-examined.
 */

type Log = { begin: number; consume: number; insert: number; commit: number; rollback: number; release: number };

function fakePool(log: Log, failInsert: boolean) {
  return {
    connect: async () => {
      let open = false;
      return {
        async query(sql: string) {
          const s = sql.trim().toLowerCase();
          if (s === "begin") { open = true; log.begin += 1; return { rowCount: 0, rows: [] }; }
          if (s === "commit") { open = false; log.commit += 1; return { rowCount: 0, rows: [] }; }
          if (s === "rollback") { open = false; log.rollback += 1; return { rowCount: 0, rows: [] }; }
          if (open && s.startsWith("update public.oppa_step_up_challenges set consumed_at")) {
            log.consume += 1;
            return { rowCount: 1, rows: [] };
          }
          if (open && s.startsWith("insert into public.oppa_step_up_challenges")) {
            if (failInsert) {
              const err = new Error("duplicate key value violates unique constraint") as Error & { code?: string };
              err.code = "23505";
              throw err;
            }
            log.insert += 1;
            return { rowCount: 1, rows: [{ id: "c1" }] };
          }
          return { rowCount: 0, rows: [] };
        },
        release() { log.release += 1; }
      };
    }
  };
}

const CHALLENGE_INPUT = {
  userId: "u1", deviceId: "d1", purpose: "wallet_transfer" as const,
  challengeHash: "hash", expiresAt: new Date(Date.now() + 60_000), maxAttempts: 5
};

test("challenge creation opens a transaction, consumes, inserts and commits in order", async () => {
  const { PostgresSecurityProofRepository: Repo } = await import("./postgres-security-proof-repository.js");
  const log: Log = { begin: 0, consume: 0, insert: 0, commit: 0, rollback: 0, release: 0 };
  const repo = new Repo(fakePool(log, false) as any);
  await repo.createChallenge(CHALLENGE_INPUT);
  assert.equal(log.begin, 1);
  assert.equal(log.consume, 1, "consume runs inside the transaction");
  assert.equal(log.insert, 1, "insert runs inside the transaction");
  assert.equal(log.commit, 1);
  assert.equal(log.rollback, 0);
  assert.equal(log.release, 1, "client is always released");
});

test("a failed insert rolls back the consume so no challenge is silently lost", async () => {
  const { PostgresSecurityProofRepository: Repo } = await import("./postgres-security-proof-repository.js");
  const log: Log = { begin: 0, consume: 0, insert: 0, commit: 0, rollback: 0, release: 0 };
  const repo = new Repo(fakePool(log, true) as any);
  await assert.rejects(
    () => repo.createChallenge(CHALLENGE_INPUT),
    (e: Error) => e.message === "STEP_UP_CHALLENGE_CONFLICT"
  );
  assert.equal(log.begin, 1);
  assert.equal(log.consume, 1, "consume attempted inside the transaction");
  assert.equal(log.commit, 0, "no commit after failure");
  assert.equal(log.rollback, 1, "consume is rolled back with the transaction");
  assert.equal(log.release, 1, "client is still released after failure");
});
