import type {
  NormalizedSmsResult,
  SendSmsInput,
  SendOutcome,
  SmsProvider
} from "./types.js";

/**
 * BulkSMS Nigeria adapter (API v2).
 *
 * API shape verified against https://www.bulksmsnigeria.com/api:
 *   POST {BASE_URL}/api/v2/sms
 *   headers: Authorization: Bearer <token>
 *   body: { from, to, body, gateway: "otp", callback_url? }
 *   200 response: { status: "success", code: "BSNG-0000",
 *                   data: { message_id, cost, recipients_count, ... } }
 *
 * - `to` must be a single number in local international format (2347...).
 * - `gateway: "otp"` is the transactional route for OTP messages.
 * - Timeout is endpoint-safe: outcome UNKNOWN, gateway decides failover.
 */
export class BulkSmsProvider implements SmsProvider {
  readonly name = "bulksms";

  constructor(
    private readonly config: {
      baseUrl: string;
      apiToken: string;
      senderId: string;
      callbackUrl?: string;
      timeoutMs: number;
    }
  ) {}

  async send(input: SendSmsInput): Promise<NormalizedSmsResult> {
    const base = this.config.baseUrl.replace(/\/+$/, "");
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.config.timeoutMs);
    try {
      const response = await fetch(`${base}/api/v2/sms`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${this.config.apiToken}`,
          "Content-Type": "application/json",
          Accept: "application/json"
        },
        body: JSON.stringify({
          from: input.senderId ?? this.config.senderId,
          to: input.to.replace(/^\+/, ""),
          body: input.message,
          gateway: "otp",
          ...(input.callbackUrl ? { callback_url: input.callbackUrl } : {})
        }),
        signal: controller.signal
      });

      const raw = await response.text();
      let data: Record<string, unknown> = {};
      try {
        data = JSON.parse(raw) as Record<string, unknown>;
      } catch {
        // Non-JSON body: classified below as provider_rejected.
      }

      const nested = data.data as Record<string, unknown> | undefined;
      const ok = response.ok && data.status === "success";
      if (!ok) {
        return {
          provider: this.name,
          outcome: "failed",
          error: {
            kind: "provider_rejected",
            httpStatus: response.status,
            providerCode: typeof data.code === "string" ? data.code : undefined
          }
        };
      }

      const messageId =
        typeof nested?.message_id === "string" ? nested.message_id :
        typeof data.message_id === "string" ? data.message_id : undefined;

      if (!messageId) {
        return { provider: this.name, outcome: "unknown", error: { kind: "ambiguous_response" } };
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
