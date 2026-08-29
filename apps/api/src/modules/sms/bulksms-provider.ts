import { env } from "../../config/env.js";
import type { SendSmsInput, SendSmsResult, SmsProvider } from "./types.js";

export class BulkSmsProvider implements SmsProvider {
  readonly name = "bulksms-nigeria";

  async send(input: SendSmsInput): Promise<SendSmsResult> {
    if (!env.bulkSmsApiToken) {
      throw new Error("BULKSMS_API_TOKEN is not configured");
    }

    const response = await fetch(`${env.bulkSmsBaseUrl}/sms`, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        Authorization: `Bearer ${env.bulkSmsApiToken}`
      },
      body: JSON.stringify({
        from: input.senderId,
        to: input.to,
        body: input.message,
        gateway: "otp",
        ...(input.callbackUrl ? { callback_url: input.callbackUrl } : {})
      })
    });

    const raw = await response.text();
    let data: Record<string, unknown> = {};
    try {
      data = JSON.parse(raw) as Record<string, unknown>;
    } catch {
      // Preserve a useful provider error below.
    }

    if (!response.ok || data.status === "error") {
      const message = typeof data.message === "string" ? data.message : raw.slice(0, 500);
      throw new Error(`BulkSMS request failed (${response.status}): ${message}`);
    }

    const nested = data.data as Record<string, unknown> | undefined;
    const providerMessageId =
      typeof nested?.message_id === "string" ? nested.message_id :
      typeof nested?.id === "string" ? nested.id :
      typeof data.message_id === "string" ? data.message_id :
      typeof data.id === "string" ? data.id : undefined;

    return {
      provider: this.name,
      providerMessageId,
      status: "submitted"
    };
  }
}
