import type { SmsAttempt, SmsAttemptRepository } from "./types.js";
import { db } from "../../db/pool.js";

function requireDb() {
  if (!db) throw new Error("DATABASE_URL is not configured");
  return db;
}

/**
 * Durable attempt ledger for SMS sends. Every provider attempt — accepted,
 * failed, or unknown — is recorded so failover is auditable and the
 * per-challenge rate budget survives process restarts.
 */
export class PostgresSmsAttemptRepository implements SmsAttemptRepository {
  async record(attempt: SmsAttempt): Promise<void> {
    await requireDb().query(
      `insert into public.oppa_sms_delivery_attempts
       (challenge_id, provider, outcome, provider_message_id, provider_request_ref, error_kind, attempted_at)
       values ($1, $2, $3, $4, $5, $6, $7)`,
      [
        attempt.challengeId,
        attempt.provider,
        attempt.outcome,
        attempt.providerMessageId ?? null,
        attempt.providerRequestRef ?? null,
        attempt.errorKind ?? null,
        attempt.attemptedAt
      ]
    );
  }

  async countForChallengeSince(challengeId: string, since: Date): Promise<number> {
    const result = await requireDb().query(
      `select count(*)::int as count
       from public.oppa_sms_delivery_attempts
       where challenge_id = $1 and attempted_at >= $2`,
      [challengeId, since]
    );
    return Number(result.rows[0]?.count ?? 0);
  }

  async hasSubmittedAttempt(challengeId: string): Promise<boolean> {
    const result = await requireDb().query(
      `select 1
       from public.oppa_sms_delivery_attempts
       where challenge_id = $1
         and outcome in ('accepted','unknown')
       limit 1`,
      [challengeId]
    );
    return (result.rowCount ?? 0) > 0;
  }
}
