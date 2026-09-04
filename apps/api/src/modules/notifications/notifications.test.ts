import assert from "node:assert/strict";
import test from "node:test";
import { NotificationService, nextBackoff, type NotificationStore, type ClaimedEvent } from "./notification-service.js";
import type { NotificationPreferences } from "./postgres-notification-repository.js";

function store(overrides: Partial<NotificationStore> = {}): NotificationStore {
  return {
    async enqueue() { return { id: "e1", deduplicated: false }; },
    async claimDueEvents() { return []; },
    async deliverInApp() {},
    async markFailed() {},
    async skip() {},
    async preferences() {
      return { security: true, device: true, message: true, wallet: true, payment: true, support: true, business: true };
    },
    ...overrides
  };
}

function event(overrides: Partial<ClaimedEvent> = {}): ClaimedEvent {
  return {
    id: "e1", userId: "u1", eventType: "wallet.transfer.completed",
    payload: { category: "wallet", title: "Transfer sent", body: "You sent money", metadata: {} },
    attempts: 1, maxAttempts: 5,
    ...overrides
  };
}

test("processBatch delivers due events", async () => {
  const delivered: string[] = [];
  const svc = new NotificationService(store({
    async claimDueEvents(limit, now) {
      assert.equal(limit, 10);
      assert.ok(now instanceof Date);
      return [event({ id: "e1" }), event({ id: "e2" })];
    },
    async deliverInApp(e) { delivered.push(e.id); }
  }));
  const result = await svc.processBatch(10);
  assert.deepEqual(result, { delivered: 2, skipped: 0, failed: 0 });
  assert.deepEqual(delivered, ["e1", "e2"]);
});

test("processBatch skips events whose category is disabled by the user", async () => {
  const calls: string[] = [];
  const prefs: NotificationPreferences = {
    security: true, device: true, message: true, wallet: false, payment: true, support: true, business: true
  };
  const svc = new NotificationService(store({
    async claimDueEvents() { return [event()]; },
    async preferences() { return prefs; },
    async skip(id) { calls.push(`skip:${id}`); },
    async deliverInApp() { calls.push("deliver"); }
  }));
  const result = await svc.processBatch(10);
  assert.deepEqual(result, { delivered: 0, skipped: 1, failed: 0 });
  assert.deepEqual(calls, ["skip:e1"]);
});

test("failed deliveries are requeued with backoff and counted once exhausted", async () => {
  const failures: Array<{ id: string; error: string; next: Date }> = [];
  const svc = new NotificationService(store({
    async claimDueEvents() { return [event({ attempts: 1 }), event({ id: "e2", attempts: 5 })]; },
    async deliverInApp(e) { if (e.id === "e2") throw new Error("DELIVERY_DOWN"); throw new Error("DB_TIMEOUT"); }
  }));
  const patched = svc as unknown as { store: NotificationStore };
  const originalMarkFailed = patched.store.markFailed.bind(patched.store);
  patched.store.markFailed = async (id, error, next) => { failures.push({ id, error, next }); await originalMarkFailed(id, error, next); };
  const result = await svc.processBatch(10);
  assert.equal(result.delivered, 0);
  assert.equal(result.failed, 1);
  assert.equal(failures.length, 2);
  assert.ok(failures[0].next.getTime() > Date.now());
});

test("backoff grows exponentially", () => {
  const first = nextBackoff(1).getTime();
  const second = nextBackoff(2).getTime();
  const third = nextBackoff(3).getTime();
  assert.ok(second - first >= 30_000 - 1_000);
  assert.ok(third - second >= 60_000 - 1_000);
});
