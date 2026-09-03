import type { TransferCounters, WalletLimits } from "./risk-repository.js";

export type LimitFailureReason =
  | "LIMIT_SINGLE_TRANSFER_EXCEEDED"
  | "LIMIT_DAILY_TOTAL_EXCEEDED"
  | "LIMIT_DAILY_COUNT_EXCEEDED";

export type TransferLimitAssessment = {
  allowed: boolean;
  reason: LimitFailureReason | null;
};

/**
 * Deterministic limit check for a single transfer. Pure so the same rules are
 * unit-tested and enforced inside the wallet transfer transaction.
 */
export function assessTransferLimits(
  limits: WalletLimits,
  counters: TransferCounters,
  amountMinor: number
): TransferLimitAssessment {
  if (amountMinor > limits.maxSingleTransferMinor) {
    return { allowed: false, reason: "LIMIT_SINGLE_TRANSFER_EXCEEDED" };
  }
  if (counters.totalMinor + amountMinor > limits.maxDailyTotalMinor) {
    return { allowed: false, reason: "LIMIT_DAILY_TOTAL_EXCEEDED" };
  }
  if (counters.count + 1 > limits.maxDailyCount) {
    return { allowed: false, reason: "LIMIT_DAILY_COUNT_EXCEEDED" };
  }
  return { allowed: true, reason: null };
}