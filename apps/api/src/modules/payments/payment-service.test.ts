import assert from "node:assert/strict";
import test from "node:test";
import { PaymentService } from "./payment-service.js";
import type { PaymentProvider, VerifiedPayment } from "./payment-provider.js";
import type { PaymentRecord, PaymentRepository } from "./payment-repository.js";
import type { RiskService } from "../risk/risk-service.js";

function provider(): PaymentProvider {
  return {
    name: "paystack" as const,
    async initialize() { return { authorizationUrl: "https://checkout.test" }; },
    async verify() { return { reference: "OPPA_1", transactionId: "tx-1", amountMinor: 5000, currency: "NGN", status: "success" } as VerifiedPayment; },
    verifyWebhook() { return true; }
  };
}

function payment(overrides: Partial<PaymentRecord> = {}): PaymentRecord {
  return { id: "pay-1", userId: "u1", provider: "paystack", reference: "OPPA_1", providerTransactionId: null, amountMinor: 5000, currency: "NGN", status: "pending", authorizationUrl: null, ...overrides };
}

function repo(overrides: Partial<PaymentRepository> = {}): PaymentRepository & { calls: string[] } {
  const calls: string[] = [];
  return {
    calls,
    async create(input: any) { calls.push("create"); return payment(); },
    async find() { return null; },
    async findById() { return payment(); },
    async findByProviderReference() { calls.push("findByProviderReference"); return payment(); },
    async list() { return []; },
    async countRecent() { calls.push("countRecent"); return { paid: 0, failed: 0 }; },
    async setRisk(id, score, decision, reasons) { calls.push(`setRisk:${decision}`); return payment({ riskScore: score, riskDecision: decision }); },
    async markPaidAndCredit(input: any) { calls.push("markPaidAndCredit"); return payment({ status: "paid", providerTransactionId: input.transactionId }); },
    async markFailed() { calls.push("markFailed"); },
    async reverseAndDebit(input: any) { calls.push("reverseAndDebit"); return payment({ status: "reversed" }); },
    ...overrides
  };
}

function risk(decision: "block" | "review" | null, events: string[] = []): RiskService {
  return {
    async getActiveDecision() { return decision; },
    async recordEvent(input: any) { events.push(`${input.category}:${input.signal}`); },
    async listDecisions() { return []; },
    async listRecentEvents() { return []; }
  } as unknown as RiskService;
}

const providers = { paystack: provider(), flutterwave: provider() } as any;

test("settles a webhook when risk allows", async () => {
  const r = repo();
  const service = new PaymentService(r, providers, undefined, risk(null));
  const result = await service.handleWebhook("paystack", Buffer.from('{"data":{"reference":"OPPA_1"}}'), "sig");
  assert.equal(result.status, "paid");
  assert.ok(r.calls.includes("countRecent"));
  assert.ok(r.calls.includes("markPaidAndCredit"));
});

test("refuses settlement while an operator payment block is active", async () => {
  const events: string[] = [];
  const r = repo();
  const service = new PaymentService(r, providers, undefined, risk("block", events));
  await assert.rejects(service.handleWebhook("paystack", Buffer.from('{"data":{"reference":"OPPA_1"}}'), "sig"), { message: "PAYMENT_RISK_BLOCKED" });
  assert.ok(!r.calls.includes("markPaidAndCredit"));
  assert.ok(events.includes("payment_anomaly:operator_block"));
});

test("refuses settlement while an operator review is active", async () => {
  const r = repo();
  const service = new PaymentService(r, providers, undefined, risk("review"));
  await assert.rejects(service.handleWebhook("paystack", Buffer.from('{"data":{"reference":"OPPA_1"}}'), "sig"), { message: "PAYMENT_REQUIRES_REVIEW" });
  assert.ok(!r.calls.includes("markPaidAndCredit"));
});

test("uses real payment counters in the risk decision", async () => {
  const events: string[] = [];
  const r = repo({ async countRecent() { return { paid: 6, failed: 4 }; } });
  const service = new PaymentService(r, providers, undefined, risk(null, events));
  await assert.rejects(service.handleWebhook("paystack", Buffer.from('{"data":{"reference":"OPPA_1"}}'), "sig"), { message: "PAYMENT_REQUIRES_REVIEW" });
  assert.ok(events.includes("payment_anomaly:risk_review"));
  assert.ok(r.calls.includes("setRisk:review"));
});

test("never credits the wallet without a verified webhook", async () => {
  const r = repo();
  const bad = { ...provider(), verifyWebhook: () => false };
  const service = new PaymentService(r, { paystack: bad, flutterwave: bad }, undefined, risk(null));
  await assert.rejects(service.handleWebhook("paystack", Buffer.from("{}"), "bad"), { message: "PAYMENT_WEBHOOK_INVALID" });
  assert.ok(!r.calls.includes("markPaidAndCredit"));
});