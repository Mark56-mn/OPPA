import assert from "node:assert/strict";
import test from "node:test";

/**
 * Regression coverage for OPPA-native call transaction invariants:
 *
 * 1. Conversation membership is verified INSIDE the mutating transaction, so a
 *    user removed from a conversation cannot start, answer, decline or hang up
 *    a call by racing or replaying an old call id.
 * 2. Every path — success, benign no-op (not-found) and failure — closes the
 *    transaction and releases the pooled client. A leaked open transaction on a
 *    pooled client would poison the pool (subsequent queries on it would run
 *    inside an abandoned transaction).
 *
 * The fake pg client mirrors the exact SQL used by PostgresCallsStore. If the
 * store's SQL drifts so the invariant breaks, these tests fail and the
 * invariant must be re-examined.
 */

type Log = {
  begin: number; commit: number; rollback: number; release: number;
  memberChecks: number; callInserts: number; eventInserts: number; callUpdates: number;
};

interface FakeOptions {
  isMember: boolean;
  callRow?: { id: string; status: string; caller_user_id: string; conversation_id: string } | null;
  failCallInsert?: boolean;
}

function fakePool(log: Log, opts: FakeOptions) {
  const inTx = () => log.begin > log.commit + log.rollback;
  return {
    connect: async () => ({
      async query(sql: string) {
        const s = sql.trim().toLowerCase();
        if (s === "begin") { log.begin += 1; return { rowCount: 0, rows: [] }; }
        if (s === "commit") { log.commit += 1; return { rowCount: 0, rows: [] }; }
        if (s === "rollback") { log.rollback += 1; return { rowCount: 0, rows: [] }; }
        if (s.includes("from public.oppa_conversation_members") && s.includes("select 1")) {
          log.memberChecks += 1;
          return { rowCount: opts.isMember ? 1 : 0, rows: opts.isMember ? [{ "?column?": 1 }] : [] };
        }
        if (s.includes("select user_id from public.oppa_conversation_members")) {
          return { rowCount: 1, rows: [{ user_id: "u1" }, { user_id: "u2" }] };
        }
        if (s.includes("from public.oppa_calls") && s.includes("for update")) {
          return { rowCount: opts.callRow ? 1 : 0, rows: opts.callRow ? [opts.callRow] : [] };
        }
        if (s.includes("from public.oppa_calls") && s.includes("status = 'ringing'")) {
          return { rowCount: 0, rows: [] }; // No pre-existing own ringing call.
        }
        if (s.includes("from public.oppa_calls") && s.includes("status = 'active'")) {
          return { rowCount: 0, rows: [] }; // No other active call (busy check).
        }
        if (s.startsWith("insert into public.oppa_calls")) {
          if (opts.failCallInsert) throw new Error("connection terminated");
          log.callInserts += 1;
          return {
            rowCount: 1,
            rows: [{
              id: "call1", conversationId: "conv1", callerUserId: "u1",
              kind: "audio", status: "ringing", endReason: null,
              startedAt: new Date(), answeredAt: null, endedAt: null, metadata: {}
            }]
          };
        }
        if (s.startsWith("insert into public.oppa_call_events")) {
          log.eventInserts += 1;
          return { rowCount: 1, rows: [{ seq: 1 }] };
        }
        if (s.startsWith("update public.oppa_calls")) {
          log.callUpdates += 1;
          return {
            rowCount: 1,
            rows: [{
              id: "call1", conversationId: "conv1", callerUserId: "u1",
              kind: "audio", status: "active", endReason: "answered",
              startedAt: new Date(), answeredAt: new Date(), endedAt: null, metadata: {}
            }]
          };
        }
        return { rowCount: 0, rows: [] };
      },
      release() { log.release += 1; }
    })
  } as any;
}

test("startCall verifies membership inside the transaction and releases the client", async () => {
  const { PostgresCallsStore: Store } = await import("./calls-service.js");
  const log: Log = { begin: 0, commit: 0, rollback: 0, release: 0, memberChecks: 0, callInserts: 0, eventInserts: 0, callUpdates: 0 };
  const store = new Store(fakePool(log, { isMember: true }));
  const { call, inviteSeq } = await store.startCall({ conversationId: "conv1", callerId: "u1", kind: "audio" });
  assert.equal(call.id, "call1");
  assert.equal(inviteSeq, 1);
  assert.equal(log.begin, 1);
  assert.equal(log.memberChecks, 1, "membership is checked inside the transaction");
  assert.equal(log.callInserts, 1);
  assert.equal(log.eventInserts, 2, "invite fanned out to both members");
  assert.equal(log.commit, 1);
  assert.equal(log.rollback, 0);
  assert.equal(log.release, 1, "client is always released");
});

test("startCall rejects a non-member with rollback and no call row", async () => {
  const { PostgresCallsStore: Store } = await import("./calls-service.js");
  const log: Log = { begin: 0, commit: 0, rollback: 0, release: 0, memberChecks: 0, callInserts: 0, eventInserts: 0, callUpdates: 0 };
  const store = new Store(fakePool(log, { isMember: false }));
  await assert.rejects(
    () => store.startCall({ conversationId: "conv1", callerId: "attacker", kind: "audio" }),
    (e: Error) => e.message === "CONVERSATION_NOT_FOUND"
  );
  assert.equal(log.memberChecks, 1);
  assert.equal(log.callInserts, 0, "no call is created for a non-member");
  assert.equal(log.commit, 0);
  assert.equal(log.rollback, 1, "the transaction is rolled back");
  assert.equal(log.release, 1, "client is still released");
});

test("a failed call insert rolls back cleanly and releases the client", async () => {
  const { PostgresCallsStore: Store } = await import("./calls-service.js");
  const log: Log = { begin: 0, commit: 0, rollback: 0, release: 0, memberChecks: 0, callInserts: 0, eventInserts: 0, callUpdates: 0 };
  const store = new Store(fakePool(log, { isMember: true, failCallInsert: true }));
  await assert.rejects(() => store.startCall({ conversationId: "conv1", callerId: "u1", kind: "audio" }));
  assert.equal(log.begin, 1);
  assert.equal(log.commit, 0);
  assert.equal(log.rollback, 1);
  assert.equal(log.release, 1);
});

test("answerCall by a non-member is a benign no-op with a closed transaction", async () => {
  const { PostgresCallsStore: Store } = await import("./calls-service.js");
  const log: Log = { begin: 0, commit: 0, rollback: 0, release: 0, memberChecks: 0, callInserts: 0, eventInserts: 0, callUpdates: 0 };
  const store = new Store(fakePool(log, { isMember: false, callRow: null }));
  const result = await store.answerCall("conv1", "call1", "attacker");
  assert.equal(result, null);
  assert.equal(log.callUpdates, 0, "no state change for a non-member");
  assert.equal(log.rollback, 1, "the open transaction is closed, not leaked");
  assert.equal(log.release, 1, "client is released");
});

test("answerCall transitions a ringing call and appends answer events", async () => {
  const { PostgresCallsStore: Store } = await import("./calls-service.js");
  const log: Log = { begin: 0, commit: 0, rollback: 0, release: 0, memberChecks: 0, callInserts: 0, eventInserts: 0, callUpdates: 0 };
  const store = new Store(fakePool(log, {
    isMember: true,
    callRow: { id: "call1", status: "ringing", caller_user_id: "u1", conversation_id: "conv1" }
  }));
  const call = await store.answerCall("conv1", "call1", "u2");
  assert.equal(call?.status, "active");
  assert.equal(log.callUpdates, 1);
  assert.equal(log.eventInserts, 1, "answer event appended");
  assert.equal(log.commit, 1);
  assert.equal(log.release, 1);
});
