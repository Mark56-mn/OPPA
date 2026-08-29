import { env } from "../../config/env.js";
import type { SendSmsInput, SendSmsResult, SmsProvider } from "./types.js";

export class BulkSmsProvider implements SmsProvider {
  readonly name = "bulksms-nigeria";

  async send(input: SendSmsInput): Promise<SendSmsResult> {
    if (!env.bulkSmsApiToken) {
      throw new Error("BULKSMS_API_TOKEN is not configured");
    }

    const response = await fetch(`${env.bulkSmsBaseUrl}/api/sms`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${env.bulkSmsApiToken}`
      },
      body: JSON.stringify({
        to: input.to,
        message: input.message,
        sender_id: input.senderId,
        callback_url: input.callbackUrl
      })
    });

    if (!response.ok) {
      const body = await response.text();
      throw new Error(`BulkSMS request failed (${response.status}): ${body.slice(0, 500)}`);
    }

    const data = (await response.json()) as Record<string, unknown>;
    const providerMessageId =
      typeof data.message_id === "string" ? data.message_id :
      typeof data.messageId === "string" ? data.messageId :
      typeof data.id === "string" ? data.id : undefined;

    return {
      provider: this.name,
      providerMessageId,
      status: "submitted"
    };
  }
}
