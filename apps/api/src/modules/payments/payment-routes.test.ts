import assert from "node:assert/strict";
import test from "node:test";
import type { AddressInfo } from "node:net";
import express from "express";
import { errorHandler } from "../../http/error-handler.js";
import { createPaymentRouter } from "./payment-routes.js";
import { PaymentService } from "./payment-service.js";
import type { PaymentRepository, PaymentRecord } from "./payment-repository.js";
import type { SensitiveAuthorization, AuthorizationProof, SensitiveOperation } from "../security/sensitive-authorization.js";

function paymentRecord(overrides: Partial<PaymentRecord> = {}): PaymentRecord {
  return {
    id: "pay-1", userId: "u1", provider: "paystack", reference: "OPPA_1", providerTransactionId: "tx-1",
    amountMinor: 50000, currency: "NGN", status: "paid", authorizationUrl: null, createdAt: new Date().toISOString(), paidAt: new Date().toISOString(), ...overrides
  };
}

function repo(calls: Array<Record<string, unknown>>, existing: PaymentRecord | null): PaymentRepository {
  return {
    async create(input: any) { calls.push({ create: input }); return paymentRecord(); },
    async find() { return existing; },
    async findById(userId: string, paymentId: string) { calls.push({ findById: { userId, paymentId } }); return existing && existing.userId === userId && existing.id === paymentId ? existing : null; },
    async findByProviderReference() { return existing; },
    async list() { return []; },
    async countRecent() { return { paid: 0, failed: 0 }; },
    async setRisk() { return paymentRecord(); },
    async markPaidAndCredit(input: any) { calls.push({ markPaidAndCredit: input }); return paymentRecord(); },
    async markFailed() {},
    async reverseAndDebit(input: any) { calls.push({ reverseAndDebit: input }); return paymentRecord({ status: "reversed" }); }
  };
}

function authorization(calls: Array<{ operation: SensitiveOperation; intent: Record<string, unknown> }>, shouldFail: boolean): SensitiveAuthorization {
  return {
    async authorize(input: { userId: string; operation: SensitiveOperation; proof: AuthorizationProof; intent?: Record<string, unknown> }) {
      calls.push({ operation: input.operation, intent: input.intent ?? {} });
      if (shouldFail) throw new Error("DEVICE_PROOF_INVALID");
      return true;
    }
  };
}

async function listen(app: express.Express): Promise<{ url: string; close: () => Promise<void> }> {
  const server = await new Promise<import("node:http").Server>((resolve) => {
    const s = app.listen(0, "127.0.0.1", () => resolve(s));
  });
  const { port } = server.address() as AddressInfo;
  return { url: `http://127.0.0.1:${port}`, close: () => new Promise((resolve) => server.close(() => resolve())) };
}

function appFor(service: PaymentService) {
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => { req.auth = { userId: "u1", sessionId: "s1" }; next(); });
  app.use("/payments", createPaymentRouter(service));
  app.use(errorHandler);
  return app;
}

const proof = { deviceId: "d1", challenge: "challenge", signature: "signature" };
const providers = { paystack: {}, flutterwave: {} } as any;

test("reversal requires and receives intent-bound authorization before debiting", async () => {
  const repoCalls: Array<Record<string, unknown>> = [];
  const authCalls: Array<{ operation: SensitiveOperation; intent: Record<string, unknown> }> = [];
  const service = new PaymentService(repo(repoCalls, paymentRecord()), providers, authorization(authCalls, false));
  const srv = await listen(appFor(service));
  try {
    const res = await fetch(`${srv.url}/payments/reverse`, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ paymentId: "pay-1", reason: "duplicate charge", ...proof })
    });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.status, "reversed");
    assert.deepEqual(authCalls, [{ operation: "payment_reversal", intent: { paymentId: "pay-1", reference: "OPPA_1", amountMinor: 50000, currency: "NGN" } }]);
    assert.ok(repoCalls.some((c) => "reverseAndDebit" in c), "reverseAndDebit must be called");
  } finally { await srv.close(); }
});

test("reversal fails closed when authorization is rejected", async () => {
  const repoCalls: Array<Record<string, unknown>> = [];
  const service = new PaymentService(repo(repoCalls, paymentRecord()), providers, authorization([], true));
  const srv = await listen(appFor(service));
  try {
    const res = await fetch(`${srv.url}/payments/reverse`, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ paymentId: "pay-1", reason: "duplicate charge", ...proof })
    });
    assert.equal(res.status, 401);
    assert.ok(!repoCalls.some((c) => "reverseAndDebit" in c), "reverseAndDebit must not run without authorization");
  } finally { await srv.close(); }
});

test("reversal rejects payments that do not belong to the caller", async () => {
  const repoCalls: Array<Record<string, unknown>> = [];
  const service = new PaymentService(repo(repoCalls, paymentRecord({ userId: "someone-else" })), providers, authorization([], false));
  const srv = await listen(appFor(service));
  try {
    const res = await fetch(`${srv.url}/payments/reverse`, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ paymentId: "pay-1", reason: "duplicate charge", ...proof })
    });
    assert.equal(res.status, 404);
    assert.ok(!repoCalls.some((c) => "reverseAndDebit" in c));
  } finally { await srv.close(); }
});

test("reversal validates the payment id and reason", async () => {
  const repoCalls: Array<Record<string, unknown>> = [];
  const authCalls: Array<{ operation: SensitiveOperation; intent: Record<string, unknown> }> = [];
  const service = new PaymentService(repo(repoCalls, paymentRecord()), providers, authorization(authCalls, false));
  const srv = await listen(appFor(service));
  try {
    const missingId = await fetch(`${srv.url}/payments/reverse`, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ reason: "duplicate charge", ...proof })
    });
    assert.equal(missingId.status, 404);
    const missingReason = await fetch(`${srv.url}/payments/reverse`, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ paymentId: "pay-1", ...proof })
    });
    assert.equal(missingReason.status, 400);
    assert.deepEqual(authCalls, []);
    assert.deepEqual(repoCalls, []);
  } finally { await srv.close(); }
});