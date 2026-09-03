import assert from "node:assert/strict";
import test from "node:test";
import { evaluatePaymentRisk } from "./payment-risk.js";

test("allows ordinary payment activity", () => {
  assert.deepEqual(evaluatePaymentRisk({ amountMinor: 100_000, recentPaidCount: 0, recentFailedCount: 0 }), { score: 0, decision: "allow", reasons: [] });
});
test("routes elevated payment activity to review", () => {
  assert.deepEqual(evaluatePaymentRisk({ amountMinor: 20_000_000, recentPaidCount: 5, recentFailedCount: 3 }), { score: 65, decision: "review", reasons: ["ELEVATED_AMOUNT", "HIGH_PAYMENT_FREQUENCY", "RECENT_PAYMENT_FAILURES"] });
});
test("blocks a large payment with recent failures", () => {
  assert.deepEqual(evaluatePaymentRisk({ amountMinor: 50_000_000, recentPaidCount: 5, recentFailedCount: 3 }), { score: 85, decision: "block", reasons: ["LARGE_AMOUNT", "HIGH_PAYMENT_FREQUENCY", "RECENT_PAYMENT_FAILURES"] });
});
