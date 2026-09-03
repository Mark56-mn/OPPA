import assert from "node:assert/strict";
import test from "node:test";
import { evaluatePaymentRisk } from "./payment-risk.js";

test("allows a small payment with clean history", () => {
  const r = evaluatePaymentRisk({ amountMinor: 5000, recentPaidCount: 0, recentFailedCount: 0 });
  assert.equal(r.decision, "allow");
  assert.deepEqual(r.reasons, []);
});

test("scores large payments without blocking on amount alone", () => {
  assert.equal(evaluatePaymentRisk({ amountMinor: 20000000, recentPaidCount: 0, recentFailedCount: 0 }).score, 15);
  assert.equal(evaluatePaymentRisk({ amountMinor: 50000000, recentPaidCount: 0, recentFailedCount: 0 }).score, 35);
});

test("escalates on high payment frequency and recent failures", () => {
  const r = evaluatePaymentRisk({ amountMinor: 5000, recentPaidCount: 5, recentFailedCount: 3 });
  assert.equal(r.decision, "review");
  assert.ok(r.reasons.includes("HIGH_PAYMENT_FREQUENCY"));
  assert.ok(r.reasons.includes("RECENT_PAYMENT_FAILURES"));
});

test("a large payment combined with abuse signals blocks", () => {
  const r = evaluatePaymentRisk({ amountMinor: 50000000, recentPaidCount: 5, recentFailedCount: 3 });
  assert.equal(r.decision, "block");
});

test("frequent payments alone add to the score without blocking", () => {
  const r = evaluatePaymentRisk({ amountMinor: 5000, recentPaidCount: 5, recentFailedCount: 0 });
  assert.equal(r.decision, "allow");
  assert.deepEqual(r.reasons, ["HIGH_PAYMENT_FREQUENCY"]);
});