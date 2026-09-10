export type SmsDeliveryStatus =
  | "queued"
  | "submitted"
  | "delivered"
  | "failed"
  | "unknown";

/**
 * Outcome of a single send attempt against one provider.
 *
 * `accepted` — provider confirmed acceptance with a message id.
 * `failed`   — provider definitively rejected (HTTP error / error payload).
 * `unknown`  — timeout/network/ambiguous response. UNKNOWN MUST NEVER be
 *              treated as success, and callers must not blindly re-send the
 *              same SMS after unknown (duplicate-delivery risk).
 */
export type SendOutcome = "accepted" | "failed" | "unknown";

export type SmsFailureKind = "timeout" | "network" | "provider_rejected" | "ambiguous_response";

export interface SendSmsInput {
  to: string;
  message: string;
  senderId?: string;
  callbackUrl?: string;
}

export interface NormalizedSmsResult {
  provider: string;
  outcome: SendOutcome;
  providerMessageId?: string;
  /** Provider-side request identifier for support/reconciliation. */
  providerRequestRef?: string;
  error?: {
    kind: SmsFailureKind;
    httpStatus?: number;
    providerCode?: string;
  };
}

/** Back-compat surface for legacy callers/tests that model a plain provider. */
export interface SendSmsResult {
  provider: string;
  providerMessageId?: string;
  status: SmsDeliveryStatus;
}

export interface SmsProvider {
  readonly name: string;
  send(input: SendSmsInput): Promise<NormalizedSmsResult>;
}

/**
 * Persisted record of one delivery attempt (per provider). Keeping every
 * attempt — including failures and unknowns — is what makes failover auditable
 * and duplicate delivery preventable: the gateway can answer "did we already
 * submit an SMS for this challenge?" from durable state, not memory.
 */
export interface SmsAttempt {
  challengeId: string;
  provider: string;
  outcome: SendOutcome;
  providerMessageId?: string;
  providerRequestRef?: string;
  errorKind?: string;
  /** Denormalized for rate-budget accounting without extra joins. */
  attemptedAt: Date;
}

export interface SmsAttemptRepository {
  record(attempt: SmsAttempt): Promise<void>;
  /** Count attempts for one challenge across ALL providers since a time. */
  countForChallengeSince(challengeId: string, since: Date): Promise<number>;
  /** Whether any attempt for the challenge ever reached a provider. */
  hasSubmittedAttempt(challengeId: string): Promise<boolean>;
}
