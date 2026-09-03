import assert from "node:assert/strict";
import test from "node:test";
import { RiskService } from "./risk-service.js";
import type { RiskDecisionInput, RiskEventInput, RiskRepository } from "./risk-repository.js";

function repo(events: RiskEventInput[] = [], decisions: Map<string, string> = new Map()) {
  const store: RiskDecisionInput[] = [];
  const r: RiskRepository = {
    async recordEvent(input) { events.push(input); },
    async createDecision(input) { store.push(input); },
    async getActiveDecision(userId, scope) { return (decisions.get(`${userId}:${scope}`) as any) ?? null; },
    async listDecisions() { return []; },
    async listRecentEvents() { return []; },
    async getOrCreateWalletLimits() { return { maxSingleTransferMinor: 1, maxDailyTotalMinor: 1, maxDailyCount: 1 }; },
    async getTransferCounters() { return { totalMinor: 0, count: 0 }; },
    async incrementTransferCounters() {}
  };
  return { r, store, events };
}

test("records a valid risk event", async () => {
  const { r, events } = repo();
  const service = new RiskService(r);
  await service.recordEvent({ userId: "u1", category: "transfer_velocity", signal: "limit_exceeded", score: 80, decision: "block", reasons: ["LIMIT_DAILY_TOTAL_EXCEEDED"], metadata: { amountMinor: 5 } });
  assert.equal(events.length, 1);
  assert.equal(events[0].signal, "limit_exceeded");
});

test("rejects an unknown category", async () => {
  const { r } = repo();
  const service = new RiskService(r);
  await assert.rejects(service.recordEvent({ category: "nonsense" as any, signal: "x" }), { message: "RISK_CATEGORY_INVALID" });
});

test("rejects an empty signal and out-of-range scores", async () => {
  const { r } = repo();
  const service = new RiskService(r);
  await assert.rejects(service.recordEvent({ category: "otp_abuse", signal: "" }), { message: "RISK_SIGNAL_INVALID" });
  await assert.rejects(service.recordEvent({ category: "otp_abuse", signal: "x", score: 101 }), { message: "RISK_SCORE_INVALID" });
  await assert.rejects(service.recordEvent({ category: "otp_abuse", signal: "x", score: 1.5 }), { message: "RISK_SCORE_INVALID" });
});

test("returns the active decision for a scope", async () => {
  const { r } = repo([], new Map([["u1:payment", "block"]]));
  const service = new RiskService(r);
  assert.equal(await service.getActiveDecision("u1", "payment"), "block");
  assert.equal(await service.getActiveDecision("u1", "transfer"), null);
});

test("rejects an unknown decision scope", async () => {
  const { r } = repo();
  const service = new RiskService(r);
  await assert.rejects(service.getActiveDecision("u1", "nonsense" as any), { message: "RISK_SCOPE_INVALID" });
});

test("creates operator decisions through the repository", async () => {
  const { r, store } = repo();
  const service = new RiskService(r);
  await r.createDecision({ userId: "u1", scope: "user", decision: "block", reason: "chargeback pattern", createdBy: "staff-1" });
  assert.equal(store.length, 1);
  assert.equal(store[0].decision, "block");
});