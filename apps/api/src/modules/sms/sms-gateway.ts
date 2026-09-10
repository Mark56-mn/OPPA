import { env, smsProviderOrder } from "../../config/env.js";
import { BulkSmsProvider } from "./bulksms-provider.js";
import { TermiiProvider } from "./termii-provider.js";
import type {
  NormalizedSmsResult,
  SendSmsInput,
  SmsAttemptRepository,
  SmsProvider
} from "./types.js";

export type SmsGatewayMode = "live" | "unconfigured";

export interface GatewaySendResult {
  /** "accepted" — some provider confirmed acceptance. "unknown" — nobody did. */
  outcome: "accepted" | "unknown";
  provider?: string;
  providerMessageId?: string;
  /** Providers attempted, in order, with their normalized outcomes. */
  attempts: NormalizedSmsResult[];
}

/**
 * SMS gateway with primary/fallback providers, durable attempt persistence,
 * and endpoint-aware ambiguity handling.
 *
 * Rules implemented here:
 * - One logical send per challenge: we try the primary, then fall back ONLY on
 *   failure/timeout — never after an `accepted` from an earlier provider.
 * - After an UNKNOWN (timeout/network/ambiguous), we may fall back to the next
 *   provider (the primary submission may or may not have gone through — an
 *   eventual duplicate SMS on the same OTP is far less harmful than no OTP),
 *   but the fallback never re-sends on the same provider. Re-sends within one
 *   provider are forbidden: the provider's own message id dedup does not exist,
 *   so a blind retry = double SMS with the same code.
 * - A durable per-challenge attempt budget (SMS_MAX_ATTEMPTS_PER_MINUTE)
 *   bounds total provider submissions per OTP, so a flapping primary cannot
 *   spam either provider.
 * - Every attempt (including failures/unknowns) is persisted first-class, so
 *   support can answer "was an SMS actually submitted?" from the database.
 */
export class FailoverSmsGateway implements SmsProvider {
  readonly name = "failover-gateway";

  constructor(
    private readonly providers: SmsProvider[],
    private readonly attempts: SmsAttemptRepository,
    private readonly options?: { challengeId?: string; maxAttemptsPerMinute?: number }
  ) {}

  /**
   * Build a gateway wired from configuration. Providers without credentials
   * are simply absent from the chain; an empty chain yields "unconfigured"
   * mode ( OTP requests fail closed with SMS_GATEWAY_UNCONFIGURED ).
   */
  static fromConfig(attempts: SmsAttemptRepository, challengeId?: string): { gateway: FailoverSmsGateway | null; mode: SmsGatewayMode } {
    const providers: SmsProvider[] = [];
    for (const name of smsProviderOrder()) {
      if (name === "bulksms" && env.bulkSmsApiToken) {
        providers.push(new BulkSmsProvider({
          baseUrl: env.bulkSmsBaseUrl,
          apiToken: env.bulkSmsApiToken,
          senderId: env.bulkSmsSenderId,
          callbackUrl: env.bulkSmsCallbackUrl,
          timeoutMs: env.smsSendTimeoutMs
        }));
      } else if (name === "termii" && env.termiiBaseUrl && env.termiiApiKey) {
        providers.push(new TermiiProvider({
          baseUrl: env.termiiBaseUrl,
          apiKey: env.termiiApiKey,
          senderId: env.termiiSenderId,
          callbackUrl: env.termiiCallbackUrl,
          webhookSecret: env.termiiWebhookSecret,
          timeoutMs: env.smsSendTimeoutMs
        }));
      }
    }
    if (providers.length === 0) return { gateway: null, mode: "unconfigured" };
    return {
      gateway: new FailoverSmsGateway(providers, attempts, { challengeId }),
      mode: "live"
    };
  }

  async send(input: SendSmsInput): Promise<NormalizedSmsResult> {
    // Fail closed when no provider is configured: never fake success.
    if (this.providers.length === 0) {
      return {
        provider: this.name,
        outcome: "failed",
        error: { kind: "provider_rejected", providerCode: "SMS_GATEWAY_UNCONFIGURED" }
      };
    }

    const challengeId = this.options?.challengeId;
    const maxPerMinute = this.options?.maxAttemptsPerMinute ?? env.smsMaxAttemptsPerMinute;

    // Durable rate budget per challenge: no matter how many times the caller
    // retries this logical send, the total provider submissions are bounded.
    if (challengeId) {
      const used = await this.attempts.countForChallengeSince(challengeId, new Date(Date.now() - 60_000));
      if (used >= maxPerMinute) {
        return {
          provider: this.name,
          outcome: "failed",
          error: { kind: "provider_rejected", providerCode: "SMS_ATTEMPT_BUDGET_EXCEEDED" }
        };
      }
    }

    const attempts: NormalizedSmsResult[] = [];
    let accepted: NormalizedSmsResult | undefined;

    for (const provider of this.providers) {
      if (accepted) break;
      let result: NormalizedSmsResult;
      try {
        result = await provider.send(input);
      } catch (error) {
        // Adapters never throw; defensive net keeps a throw from becoming a
        // fake success or an unhandled failure path.
        result = { provider: provider.name, outcome: "unknown", error: { kind: "network" } };
        void error;
      }
      await this.attempts.record({
        challengeId: challengeId ?? "unattributed",
        provider: provider.name,
        outcome: result.outcome,
        providerMessageId: result.providerMessageId,
        providerRequestRef: result.providerRequestRef,
        errorKind: result.error?.kind,
        attemptedAt: new Date()
      });
      attempts.push(result);

      if (result.outcome === "accepted") {
        accepted = result;
      } else if (result.outcome === "unknown") {
        // Allowed: fall through to the next provider once. The budget above
        // bounds total submissions; the next provider is a different endpoint.
        continue;
      } else {
        // Definitive provider rejection: move to the fallback.
        continue;
      }
    }

    if (accepted) {
      return {
        provider: accepted.provider,
        outcome: "accepted",
        providerMessageId: accepted.providerMessageId,
        providerRequestRef: accepted.providerRequestRef
      };
    }

    // Every provider failed or timed out. Do NOT consume the budget on an
    // unknown last attempt: the caller decides (see OtpService).
    const last = attempts[attempts.length - 1];
    return {
      provider: this.name,
      outcome: "unknown",
      providerMessageId: undefined,
      error: last?.error ?? { kind: "network" }
    };
  }
}
