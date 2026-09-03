import assert from "node:assert/strict";
import test from "node:test";
import { assessTransferLimits } from "./transfer-limits.js";

const limits = { maxSingleTransferMinor: 100000, maxDailyTotalMinor: 300000, maxDailyCount: 3 };
const empty = { totalMinor: 0, count: 0 };

test("allows a transfer within every limit", () => {
  assert.deepEqual(assessTransferLimits(limits, empty, 100000), { allowed: true, reason: null });
});

test("allows a transfer exactly at the daily total boundary", () => {
  assert.deepEqual(assessTransferLimits(limits, { totalMinor: 200000, count: 1 }, 100000), { allowed: true, reason: null });
});

test("blocks a transfer over the single-transfer limit", () => {
  assert.deepEqual(assessTransferLimits(limits, empty, 100001), { allowed: false, reason: "LIMIT_SINGLE_TRANSFER_EXCEEDED" });
});

test("blocks a transfer over the daily total limit", () => {
  assert.deepEqual(assessTransferLimits(limits, { totalMinor: 200001, count: 1 }, 100000), { allowed: false, reason: "LIMIT_DAILY_TOTAL_EXCEEDED" });
});

test("blocks a transfer over the daily count limit", () => {
  assert.deepEqual(assessTransferLimits(limits, { totalMinor: 0, count: 3 }, 1000), { allowed: false, reason: "LIMIT_DAILY_COUNT_EXCEEDED" });
});

test("blocks when both total and count would be exceeded (total reported first)", () => {
  assert.deepEqual(assessTransferLimits(limits, { totalMinor: 300000, count: 3 }, 1), { allowed: false, reason: "LIMIT_DAILY_TOTAL_EXCEEDED" });
});