import assert from "node:assert/strict";
import test from "node:test";
import type { AddressInfo } from "node:net";
import express from "express";
import { errorHandler } from "../../http/error-handler.js";
import { createWalletRouter } from "./wallet-routes.js";
import type { WalletRepository } from "./wallet-repository.js";
import type { WalletTransferRepository, WalletTransferResult } from "./wallet-transfer-repository.js";
import type { SensitiveAuthorization, AuthorizationProof, SensitiveOperation } from "../security/sensitive-authorization.js";

function appWith(transfers: WalletTransferRepository, authorization?: SensitiveAuthorization) {
  const wallets: WalletRepository = {
    async getOrCreate(userId) { return { userId, currency: "NGN", balanceMinor: 0, updatedAt: new Date().toISOString() }; },
    async listTransactions() { return []; },
    async credit(userId, amountMinor, reference) { return { id: "t", userId, type: "credit", amountMinor, balanceAfterMinor: amountMinor, reference, description: null, createdAt: new Date().toISOString() }; },
    async debit(userId, amountMinor, reference) { return { id: "t", userId, type: "debit", amountMinor, balanceAfterMinor: 0, reference, description: null, createdAt: new Date().toISOString() }; }
  };
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => { req.auth = { userId: "u1", sessionId: "s1" }; next(); });
  app.use("/wallet", createWalletRouter(wallets, transfers, authorization));
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

function transferRepo(calls: Array<Record<string, unknown>>): WalletTransferRepository {
  return {
    async transfer(input: { fromUserId: string; toUserId: string; amountMinor: number; reference: string }): Promise<WalletTransferResult> {
      calls.push(input);
      return { transferId: "t1", reference: input.reference, fromUserId: input.fromUserId, toUserId: input.toUserId, amountMinor: input.amountMinor, currency: "NGN", status: "completed", createdAt: new Date().toISOString() };
    }
  };
}

function authorization(decisions: Record<string, () => void | never>, calls: Array<{ operation: SensitiveOperation; intent: Record<string, unknown> }>): SensitiveAuthorization {
  return {
    async authorize(input: { userId: string; operation: SensitiveOperation; proof: AuthorizationProof; intent?: Record<string, unknown> }) {
      calls.push({ operation: input.operation, intent: input.intent ?? {} });
      const decision = decisions[input.operation];
      if (decision) decision();
      return true;
    }
  };
}

const proof = { deviceId: "d1", challenge: "challenge", signature: "signature" };

test("transfer requires and receives server-derived intent", async () => {
  const transfers: Array<Record<string, unknown>> = [];
  const authCalls: Array<{ operation: SensitiveOperation; intent: Record<string, unknown> }> = [];
  const app = appWith(transferRepo(transfers), authorization({}, authCalls));
  const srv = await listen(app);
  try {
    const res = await fetch(`${srv.url}/wallet/transfer`, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ toUserId: "u2", amountMinor: 50000, reference: "ref-1", ...proof })
    });
    assert.equal(res.status, 201);
    assert.deepEqual(authCalls, [{ operation: "wallet_transfer", intent: { toUserId: "u2", amountMinor: 50000, currency: "NGN", reference: "ref-1" } }]);
    assert.deepEqual(transfers, [{ fromUserId: "u1", toUserId: "u2", amountMinor: 50000, reference: "ref-1" }]);
  } finally { await srv.close(); }
});

test("transfer fails closed when authorization is rejected", async () => {
  const transfers: Array<Record<string, unknown>> = [];
  const app = appWith(transferRepo(transfers), authorization({ wallet_transfer: () => { throw new Error("DEVICE_PROOF_INVALID"); } }, []));
  const srv = await listen(app);
  try {
    const res = await fetch(`${srv.url}/wallet/transfer`, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ toUserId: "u2", amountMinor: 50000, reference: "ref-1", ...proof })
    });
    assert.equal(res.status, 401);
    assert.deepEqual(transfers, []);
  } finally { await srv.close(); }
});

test("transfer is unavailable when sensitive authorization is not configured", async () => {
  const transfers: Array<Record<string, unknown>> = [];
  const app = appWith(transferRepo(transfers));
  const srv = await listen(app);
  try {
    const res = await fetch(`${srv.url}/wallet/transfer`, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ toUserId: "u2", amountMinor: 50000, reference: "ref-1", ...proof })
    });
    assert.equal(res.status, 503);
    assert.deepEqual(transfers, []);
  } finally { await srv.close(); }
});

test("transfer validates amount before touching authorization", async () => {
  const transfers: Array<Record<string, unknown>> = [];
  const authCalls: Array<{ operation: SensitiveOperation; intent: Record<string, unknown> }> = [];
  const app = appWith(transferRepo(transfers), authorization({}, authCalls));
  const srv = await listen(app);
  try {
    for (const amountMinor of [0, -1, 1.5, "100"]) {
      const res = await fetch(`${srv.url}/wallet/transfer`, {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ toUserId: "u2", amountMinor, reference: "ref-1", ...proof })
      });
      assert.equal(res.status, 400, `amount ${String(amountMinor)} should be rejected`);
    }
    assert.deepEqual(authCalls, []);
    assert.deepEqual(transfers, []);
  } finally { await srv.close(); }
});

test("transfer validates the reference and recipient before authorization", async () => {
  const transfers: Array<Record<string, unknown>> = [];
  const authCalls: Array<{ operation: SensitiveOperation; intent: Record<string, unknown> }> = [];
  const app = appWith(transferRepo(transfers), authorization({}, authCalls));
  const srv = await listen(app);
  try {
    const badReference = await fetch(`${srv.url}/wallet/transfer`, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ toUserId: "u2", amountMinor: 100, reference: "bad ref!!", ...proof })
    });
    assert.equal(badReference.status, 400);
    const missingRecipient = await fetch(`${srv.url}/wallet/transfer`, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ amountMinor: 100, reference: "ref-1", ...proof })
    });
    assert.equal(missingRecipient.status, 404);
    assert.deepEqual(authCalls, []);
    assert.deepEqual(transfers, []);
  } finally { await srv.close(); }
});