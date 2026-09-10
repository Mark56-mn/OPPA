import { createHmac, timingSafeEqual } from "node:crypto";
import type {
  NormalizedSmsResult,
  SendSmsInput,
  SendOutcome,
  SmsProvider
} from "./types.js";

/**
 * Termii SMS adapter.
 *
 * API shape verified against https://developers.termii.com/messaging-api/:
 *   POST {BASE_URL}/api/sms/send
 *   body: { api_key, to, from, sms, type: "plain", channel: "dnd" }
 *   200 response: { code: "ok", message_id, message, balance, ... }
 *
 * - The account-specific base URL comes from TERMII_BASE_URL (never hardcode a
 *   regional endpoint; the dashboard shows the correct host per account).
 * - OTP/transactional messages MUST use channel "dnd" per Termii's guidance
 *   (generic route fails on DND numbers and is blocked for MTN at night).
 * - Timeout is endpoint-safe: a timeout means the request outcome is UNKNOWN —
 *   the gateway decides failover; this adapter never retries internally.
 */
export class TermiiProvider implements SmsProvider {
  readonly name = "termii";

  constructor(
    private readonly config: {
      baseUrl: string;
      apiKey: string;
      senderId: string;
      callbackUrl?: string;
      webhookSecret?: string;
      timeoutMs: number;
    }
  ) {}

  /**
   * Verify a Termii delivery-event webhook payload. When TERMII_WEBHOOK_SECRET
   * is configured, Termii signs events with an HMAC-SHA512 hex digest of the
   * raw body in the `x-termii-signature` header (mirroring its payment-webhook
   * convention). With no secret configured the flow is disabled upstream, so
   * this returns false — callbacks must be opt-in and authenticated.
   */
  verifyWebhook(rawBody: Buffer, signature: string | undefined): boolean {
    const secret = this.config.webhookSecret;
    if (!secret || !signature) return false;
    const expected = createHmac("sha512", secret).update(rawBody).digest("hex");
    const a = Buffer.from(expected, "utf8");
    const b = Buffer.from(signature, "utf8");
    return a.length === b.length && timingSafeEqual(a, b);
  }

  /** Normalize a Termii event status string to the OPPA delivery model. */
  static normalizeEventStatus(status: string): "queued" | "submitted" | "delivered" | "failed" | "unknown" {
    switch (status) {
      case "Message sent":
        return "queued";
      case "Sending":
      case "Submitted":
        return "submitted";
      case "Delivered":
        return "delivered";
      case "Failed":
      case "Rejected":
        return "failed";
      default:
        return "unknown";
    }
  }

  async send(input: SendSmsInput): Promise<NormalizedSmsResult> {
    const base = this.config.baseUrl.replace(/\/+$/, "");
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.config.timeoutMs);
    try {
      const response = await fetch(`${base}/api/sms/send`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify({
          api_key: this.config.apiKey,
          to: input.to.replace(/^\+/, ""),
          from: input.senderId ?? this.config.senderId,
          sms: input.message,
          type: "plain",
          channel: "dnd"
        }),
        signal: controller.signal
      });

      const raw = await response.text();
      let data: Record<string, unknown> = {};
      try {
        data = JSON.parse(raw) as Record<string, unknown>;
      } catch {
        // Non-JSON body: fall through to classification with the raw snippet.
      }

      // Termii signals success with HTTP 200 AND body code "ok".
      const ok = response.ok && data.code === "ok";
      if (!ok) {
        // Malformed/HTTP-level failures are permanent for this attempt.
        return {
          provider: this.name,
          outcome: "failed",
          error: {
            kind: "provider_rejected",
            httpStatus: response.status,
            // Provider messages can embed account data; keep only the code.
            providerCode: typeof data.code === "string" ? data.code : undefined
          }
        };
      }

      const messageId = typeof data.message_id === "string" ? data.message_id : undefined;
      if (!messageId) {
        // Accepted without a message id: the send MAY have been accepted.
        // Never treat missing ids as definite success.
        return {
          provider: this.name,
          outcome: "unknown",
          error: { kind: "ambiguous_response" }
        };
      }
      return {
        provider: this.name,
        outcome: "accepted",
        providerMessageId: messageId,
        providerRequestRef: messageId
      };
    } catch (error) {
      const aborted = controller.signal.aborted;
      const kind = (error as { name?: string })?.name === "AbortError" || aborted
        ? "timeout"
        : "network";
      return { provider: this.name, outcome: "unknown", error: { kind } };
    } finally {
      clearTimeout(timer);
    }
  }
}

export type { SendOutcome };
