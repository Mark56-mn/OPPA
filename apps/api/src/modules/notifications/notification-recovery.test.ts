import assert from "node:assert/strict";
import test from "node:test";
import { NotificationService, type NotificationStore, type ClaimedEvent } from "./notification-service.js";
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

test("processBatch recovers stalled processing rows before claiming", async () => {
  const calls: string[] = [];
  const svc = new NotificationService(store({
    async recoverStalledProcessing(minutes) {
      calls.push(`recover:${minutes}`);
      assert.ok(minutes! >= 1, "recovery window must be positive");
    },
    async claimDueEvents() { calls.push("claim"); return []; }
  }));
  await svc.processBatch(10);
  assert.deepEqual(calls, ["recover:10", "claim"]);
});

test("recovery failure does not block claiming", async () => {
  const calls: string[] = [];
  const svc = new NotificationService(store({
    async recoverStalledProcessing() { throw new Error("DB_DOWN"); },
    async claimDueEvents() { calls.push("claim"); return []; }
  }));
  const result = await svc.processBatch(10);
  assert.deepEqual(result, { delivered: 0, skipped: 0, failed: 0 });
  assert.deepEqual(calls, ["claim"]);
});
