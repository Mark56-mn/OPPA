import type { SmsAttemptRepository } from "./types.js";
import type { TermiiProvider } from "./termii-provider.js";
import { db } from "../../db/pool.js";

/**
 * Persists SMS delivery callbacks into the attempt ledger. Delivery updates
 * are append-only observations: a recorded outcome is never mutated, later
 * events for the same message are no-ops (first observation wins), and the
 * recorder never mutates OTP challenges, wallets, or payments.
 */
export class SmsDeliveryRecorder {
  constructor(
    private readonly attempts: SmsAttemptRepository,
    private readonly termii?: TermiiProvider
  ) {}

  verifyTermiiWebhook(rawBody: Buffer | undefined, signature: string | undefined): boolean {
    if (!rawBody) return false;
    return this.termii?.verifyWebhook(rawBody, signature) ?? false;
  }

  async recordDelivery(input: {
    provider: "bulksms" | "termii";
    providerMessageId: string;
    recipient?: string;
    status: "delivered" | "failed" | "submitted" | "unknown";
  }): Promise<{ recorded: boolean }> {
    // Only meaningful transitions are persisted: delivered/failed states.
    // Intermediate "submitted" echoes are ignored (the send attempt already
    // recorded the submission); "unknown" callbacks carry no information.
    if (input.status !== "delivered" && input.status !== "failed") {
      return { recorded: false };
    }
    const challengeId = await this.resolveChallengeId(input.provider, input.providerMessageId);
    // Terminal DLRs ride the same ledger as send attempts with an errorKind
    // tag (`dlr:delivered` / `dlr:failed`); the outcome column keeps its
    // constraint by recording the original submission classification and
    // treating DLR rows as observations.
    await this.attempts.record({
      challengeId,
      provider: input.provider,
      outcome: "accepted",
      providerMessageId: input.providerMessageId,
      errorKind: `dlr:${input.status}`,
      attemptedAt: new Date()
    });
    return { recorded: true };
  }

  /**
   * Resolve which OTP challenge a provider message belongs to via the
   * challenge's provider_message_id column. Unknown messages are recorded as
   * "unattributed" — auditable, bounded-impact, and tolerated by the
   * FK-free ledger design.
   */
  private async resolveChallengeId(provider: string, providerMessageId: string): Promise<string> {
    try {
      if (!db) return "unattributed";
      const result = await db.query(
        `select id from public.otp_challenges where provider_message_id = $1 limit 1`,
        [providerMessageId]
      );
      const id = result.rows[0]?.id;
      return typeof id === "string" && id.length > 0 ? id : "unattributed";
    } catch {
      void provider;
      return "unattributed";
    }
  }
}
