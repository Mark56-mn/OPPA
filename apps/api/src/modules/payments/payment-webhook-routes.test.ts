import assert from "node:assert/strict";
import test from "node:test";
import type { AddressInfo } from "node:net";
import express from "express";
import { errorHandler } from "../../http/error-handler.js";
import { createPaymentWebhookRouter } from "./payment-webhook-routes.js";
import { PaymentService } from "./payment-service.js";
import type { PaymentProvider, VerifiedPayment } from "./payment-provider.js";
import type { PaymentRecord, PaymentRepository } from "./payment-repository.js";
import type { RiskService } from "../risk/risk-service.js";

// ---------------------------------------------------------------------------
// Fake wiring: real PaymentService + real webhook router. The fake repository
// mirrors the production Postgres guards one-for-one so the attack tests
// assert real behavior, not fake leniency:
//   - findByProviderReference is provider- AND reference-scoped (the SQL
//     `where provider=$1 and reference=$2`), so cross-provider confusion
//     yields PAYMENT_NOT_FOUND exactly as in production.
//   - markPaidAndCredit replicates the `for update` + `status='pending'`
//     transition: only the first settlement credits, later calls see the
//     committed paid row and short-circuit without crediting (the same
//     guarantee the row lock provides under concurrency).
// ---------------------------------------------------------------------------

function provider(overrides: Partial<PaymentProvider> = {}): PaymentProvider {
  return {
    name: "paystack" as const,
    async initialize() { return { authorizationUrl: "https://checkout.test" }; },
    // Real providers resolve exactly the reference being verified; unknown
    // references simply never settle because the local lookup misses.
    async verify(reference: string) { return { reference, transactionId: "tx-1", amountMinor: 5000, currency: "NGN", status: "success" } as VerifiedPayment; },
    verifyWebhook() { return true; },
    ...overrides
  };
}

function payment(overrides: Partial<PaymentRecord> = {}): PaymentRecord {
  return { id: "pay-1", userId: "u1", provider: "paystack", reference: "OPPA_1", providerTransactionId: null, amountMinor: 5000, currency: "NGN", status: "pending", authorizationUrl: null, ...overrides };
}

type AttackRepo = PaymentRepository & { calls: string[]; creditCalls: number; settleRow: () => PaymentRecord };

function repo(seed: Partial<PaymentRecord> = {}): AttackRepo {
  const calls: string[] = [];
  let creditCalls = 0;
  let row: PaymentRecord = payment(seed);
  return {
    get calls() { return calls; },
    get creditCalls() { return creditCalls; },
    settleRow: () => row,
    async create(input: any) { calls.push("create"); return payment(); },
    async find() { return null; },
    async findById() { return { ...row }; },
    async findByProviderReference(repoProvider: string, reference: string) {
      calls.push("findByProviderReference");
      return row.provider === repoProvider && row.reference === reference ? { ...row } : null;
    },
    async list() { return []; },
    async countRecent() { return { paid: 0, failed: 0 }; },
    async setRisk(id, score, decision, reasons) { calls.push(`setRisk:${decision}`); return { ...row, riskScore: score, riskDecision: decision }; },
    async markPaidAndCredit(input: any) {
      calls.push(`markPaidAndCredit:${input.transactionId}`);
      // Mirrors PostgresPaymentRepository.markPaidAndCredit's transactional guards.
      if (row.amountMinor !== input.amountMinor || row.currency !== "NGN") throw new Error("PAYMENT_AMOUNT_MISMATCH");
      if (row.status === "paid") {
        if (row.providerTransactionId && row.providerTransactionId !== input.transactionId) throw new Error("PAYMENT_TRANSACTION_MISMATCH");
        return { ...row }; // committed paid row; no second credit
      }
      if (row.status === "reversed") throw new Error("PAYMENT_ALREADY_REVERSED");
      if (row.riskDecision && row.riskDecision !== "allow") throw new Error(row.riskDecision === "block" ? "PAYMENT_RISK_BLOCKED" : "PAYMENT_REQUIRES_REVIEW");
      creditCalls += 1;
      row = { ...row, status: "paid", providerTransactionId: input.transactionId };
      return { ...row };
    },
    async markFailed(repoProvider: string, reference: string) {
      calls.push("markFailed");
      if (row.provider === repoProvider && row.reference === reference && row.status === "pending") row = { ...row, status: "failed" };
    },
    async reverseAndDebit(input: any) { calls.push("reverseAndDebit"); if (row.status === "paid") row = { ...row, status: "reversed" }; return { ...row }; }
  } as AttackRepo;
}

function risk(decision: "block" | "review" | null): RiskService {
  return {
    async getActiveDecision() { return decision; },
    async recordEvent() {},
    async listDecisions() { return []; },
    async listRecentEvents() { return []; }
  } as unknown as RiskService;
}

function appWith(providers: Record<string, PaymentProvider>, repository: AttackRepo, service?: PaymentService) {
  const app = express();
  // Mirror the production raw-body capture: no body parser rewrites the bytes
  // the signature covers. (Signature verification is provider-side here.)
  app.use(express.json({ verify: (req: any, _res, buf) => { (req as any).rawBody = buf; } }));
  app.use("/webhooks/payments", createPaymentWebhookRouter(service ?? new PaymentService(repository, providers as any, undefined, risk(null))));
  app.use(errorHandler);
  return app;
}

async function listen(app: express.Express): Promise<{ url: string; close: () => Promise<void> }> {
  const server = await new Promise<import("node:http").Server>((resolve) => {
    const s = app.listen(0, "127.0.0.1", () => resolve(s));
  });
  const { port } = server.address() as AddressInfo;
  return { url: `http://127.0.0.1:${port}`, close: () => new Promise((resolve) => server.close(() => resolve())) };
}

const post = (url: string, path: string, body: string, headers: Record<string, string> = {}) =>
  fetch(`${url}${path}`, { method: "POST", headers: { "content-type": "application/json", ...headers }, body });

// ---------------------------------------------------------------------------
// Attacks
// ---------------------------------------------------------------------------

test("anonymous attacker: invalid signature never reaches settlement", async () => {
  const r = repo();
  const bad = provider({ verifyWebhook: () => false });
  const srv = await listen(appWith({ paystack: bad, flutterwave: bad }, r));
  try {
    const res = await post(srv.url, "/webhooks/payments/paystack", JSON.stringify({ event: "charge.success", data: { reference: "OPPA_1" } }), { "x-paystack-signature": "forged" });
    assert.equal(res.status, 401);
    assert.equal((await res.json()).error, "PAYMENT_WEBHOOK_INVALID");
    assert.deepEqual(r.calls, []);
  } finally { await srv.close(); }
});

test("anonymous attacker: missing raw body is rejected before any provider work", async () => {
  const r = repo();
  const good = provider();
  const app = express();
  // Deliberately NO raw-body capture to prove the fail-closed path.
  app.use(express.json());
  app.use("/webhooks/payments", createPaymentWebhookRouter(new PaymentService(r, { paystack: good, flutterwave: good } as any, undefined, risk(null))));
  app.use(errorHandler);
  const srv = await listen(app);
  try {
    const res = await post(srv.url, "/webhooks/payments/paystack", JSON.stringify({ data: { reference: "OPPA_1" } }));
    assert.equal(res.status, 400);
    assert.deepEqual(r.calls, []);
  } finally { await srv.close(); }
});

test("webhook replay: duplicate delivery is idempotent and never double-credits", async () => {
  const r = repo();
  const good = provider();
  const srv = await listen(appWith({ paystack: good, flutterwave: good }, r));
  try {
    const body = JSON.stringify({ event: "charge.success", data: { reference: "OPPA_1" } });
    const first = await post(srv.url, "/webhooks/payments/paystack", body, { "x-paystack-signature": "sig" });
    assert.equal(first.status, 200);
    assert.equal(r.creditCalls, 1);
    const replay = await post(srv.url, "/webhooks/payments/paystack", body, { "x-paystack-signature": "sig" });
    assert.equal(replay.status, 200);
    const second = await replay.json();
    // The replay short-circuits at the already-paid state without crediting.
    assert.equal(second.status, "paid");
    assert.equal(r.creditCalls, 1);
    assert.equal(r.calls.filter((c) => String(c).startsWith("markPaidAndCredit")).length, 1);
  } finally { await srv.close(); }
});

test("webhook replay racing concurrently settles exactly once", async () => {
  const r = repo();
  const good = provider();
  const srv = await listen(appWith({ paystack: good, flutterwave: good }, r));
  try {
    const body = JSON.stringify({ event: "charge.success", data: { reference: "OPPA_1" } });
    const [a, b, c] = await Promise.all([
      post(srv.url, "/webhooks/payments/paystack", body, { "x-paystack-signature": "sig" }),
      post(srv.url, "/webhooks/payments/paystack", body, { "x-paystack-signature": "sig" }),
      post(srv.url, "/webhooks/payments/paystack", body, { "x-paystack-signature": "sig" })
    ]);
    for (const res of [a, b, c]) assert.ok([200, 409].includes(res.status), `concurrent replay returned ${res.status}`);
    // In production the wallets row lock serializes these; here the stateful
    // fake enforces the same single-credit invariant.
    assert.equal(r.creditCalls, 1);
  } finally { await srv.close(); }
});

test("forged reference: unknown or malformed references are rejected without settlement", async () => {
  const r = repo();
  const good = provider();
  const srv = await listen(appWith({ paystack: good, flutterwave: good }, r));
  try {
    for (const [body, expected] of [
      [JSON.stringify({ data: { reference: "does-not-exist" } }), 404],
      [JSON.stringify({ data: {} }), 400],
      [JSON.stringify({ data: { reference: { $gt: "" } } }), 400],
      [JSON.stringify({ data: { reference: "x".repeat(200) } }), 400]
    ] as const) {
      const res = await post(srv.url, "/webhooks/payments/paystack", body, { "x-paystack-signature": "sig" });
      assert.equal(res.status, expected, `${body.slice(0, 40)} -> ${res.status}`);
    }
    assert.deepEqual(r.calls.filter((c) => String(c).startsWith("markPaidAndCredit")), []);
    assert.equal(r.creditCalls, 0);
  } finally { await srv.close(); }
});

test("cross-provider confusion: paystack reference posted to flutterwave endpoint settles nothing", async () => {
  const r = repo(); // row.provider === "paystack"
  const good = provider();
  const srv = await listen(appWith({ paystack: good, flutterwave: good }, r));
  try {
    const res = await post(srv.url, "/webhooks/payments/flutterwave", JSON.stringify({ event: "charge.completed", data: { tx_ref: "OPPA_1" } }), { "verif-hash": "sig" });
    // The provider-scoped lookup (where provider=$1 and reference=$2) finds
    // nothing on the flutterwave path: PAYMENT_NOT_FOUND, no credit.
    assert.equal(res.status, 404);
    assert.equal((await res.json()).error, "PAYMENT_NOT_FOUND");
    assert.equal(r.creditCalls, 0);
  } finally { await srv.close(); }
});

test("tampered amount: provider-verified amount that differs from the recorded payment fails closed", async () => {
  const r = repo();
  const inflated = provider({ async verify() { return { reference: "OPPA_1", transactionId: "tx-1", amountMinor: 999999, currency: "NGN", status: "success" }; } });
  const srv = await listen(appWith({ paystack: inflated, flutterwave: inflated }, r));
  try {
    const res = await post(srv.url, "/webhooks/payments/paystack", JSON.stringify({ data: { reference: "OPPA_1" } }), { "x-paystack-signature": "sig" });
    assert.equal(res.status, 409);
    assert.equal((await res.json()).error, "PAYMENT_AMOUNT_MISMATCH");
    assert.equal(r.creditCalls, 0);
    assert.notEqual(r.settleRow().status, "paid");
  } finally { await srv.close(); }
});

test("tampered currency: non-NGN provider data is refused regardless of signature validity", async () => {
  const r = repo();
  const usd = provider({ async verify() { return { reference: "OPPA_1", transactionId: "tx-1", amountMinor: 5000, currency: "USD" as any, status: "success" }; } });
  const srv = await listen(appWith({ paystack: usd, flutterwave: usd }, r));
  try {
    const res = await post(srv.url, "/webhooks/payments/paystack", JSON.stringify({ data: { reference: "OPPA_1" } }), { "x-paystack-signature": "sig" });
    assert.equal(res.status, 400);
    assert.equal((await res.json()).error, "PAYMENT_CURRENCY_INVALID");
    assert.equal(r.creditCalls, 0);
  } finally { await srv.close(); }
});

test("failed provider status marks the payment failed and never credits", async () => {
  const r = repo();
  const failing = provider({ async verify() { return { reference: "OPPA_1", transactionId: "tx-1", amountMinor: 5000, currency: "NGN", status: "failed" }; } });
  const srv = await listen(appWith({ paystack: failing, flutterwave: failing }, r));
  try {
    const res = await post(srv.url, "/webhooks/payments/paystack", JSON.stringify({ data: { reference: "OPPA_1" } }), { "x-paystack-signature": "sig" });
    assert.equal(res.status, 200);
    const json = await res.json();
    assert.equal(json.status, "failed");
    assert.ok(r.calls.includes("markFailed"));
    assert.equal(r.creditCalls, 0);
    assert.equal(r.settleRow().status, "failed");
  } finally { await srv.close(); }
});

test("amount attacks: zero, negative and unsafe amounts are refused", async () => {
  const amounts = [0, -5000, Number.NaN, 1.5, Number.MAX_SAFE_INTEGER + 1];
  for (const amountMinor of amounts) {
    const r = repo();
    const evil = provider({ async verify() { return { reference: "OPPA_1", transactionId: "tx-1", amountMinor: amountMinor as number, currency: "NGN", status: "success" }; } });
    const srv = await listen(appWith({ paystack: evil, flutterwave: evil }, r));
    try {
      const res = await post(srv.url, "/webhooks/payments/paystack", JSON.stringify({ data: { reference: "OPPA_1" } }), { "x-paystack-signature": "sig" });
      assert.equal(res.status, 400, `amount ${String(amountMinor)} should be refused`);
      assert.equal((await res.json()).error, "PAYMENT_AMOUNT_INVALID");
      assert.equal(r.creditCalls, 0);
    } finally { await srv.close(); }
  }
});

test("operator risk block on the paying user stops settlement at the route", async () => {
  const r = repo();
  const good = provider();
  const service = new PaymentService(r, { paystack: good, flutterwave: good } as any, undefined, risk("block"));
  const srv = await listen(appWith({ paystack: good, flutterwave: good }, r, service));
  try {
    const res = await post(srv.url, "/webhooks/payments/paystack", JSON.stringify({ data: { reference: "OPPA_1" } }), { "x-paystack-signature": "sig" });
    assert.equal(res.status, 403);
    assert.equal((await res.json()).error, "PAYMENT_RISK_BLOCKED");
    assert.equal(r.creditCalls, 0);
  } finally { await srv.close(); }
});
