import test from "node:test";
import assert from "node:assert/strict";
import { WalletService } from "./wallet-service.js";
import type { WalletRepository, WalletTransaction } from "./wallet-repository.js";

function tx(partial: Partial<WalletTransaction> = {}): WalletTransaction {
  return {
    id: "tx-1",
    userId: "user-1",
    type: "credit",
    amountMinor: 10000,
    balanceAfterMinor: 10000,
    reference: "ref-1",
    description: null,
    createdAt: new Date().toISOString(),
    ...partial
  };
}

function repo(): WalletRepository & { calls: string[] } {
  return {
    calls: [],
    async getOrCreate(userId) { this.calls.push(`balance:${userId}`); return { userId, currency: "NGN", balanceMinor: 0, updatedAt: new Date().toISOString() }; },
    async listTransactions(userId, limit, before) { this.calls.push(`list:${userId}:${limit}:${before ?? ""}`); return []; },
    async credit(userId, amountMinor, reference, description) { this.calls.push(`credit:${userId}:${amountMinor}:${reference}`); return tx({ userId, amountMinor, reference, description: description ?? null }); },
    async debit(userId, amountMinor, reference, description) { this.calls.push(`debit:${userId}:${amountMinor}:${reference}`); return tx({ userId, type: "debit", amountMinor, reference, description: description ?? null }); }
  };
}

test("wallet service delegates balance reads", async () => {
  const r = repo();
  const service = new WalletService(r);
  await service.getBalance("user-1");
  assert.deepEqual(r.calls, ["balance:user-1"]);
});

test("wallet service delegates transaction history", async () => {
  const r = repo();
  const service = new WalletService(r);
  await service.getTransactions("user-1", 25, "2026-08-31T00:00:00.000Z");
  assert.deepEqual(r.calls, ["list:user-1:25:2026-08-31T00:00:00.000Z"]);
});

test("wallet service keeps mutations behind its service boundary", async () => {
  const r = repo();
  const service = new WalletService(r);
  await service.credit("user-1", 50000, "payment-1", "Funding");
  await service.debit("user-1", 12000, "transfer-1", "Transfer");
  assert.deepEqual(r.calls, ["credit:user-1:50000:payment-1", "debit:user-1:12000:transfer-1"]);
});
