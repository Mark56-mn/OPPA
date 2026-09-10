import { Router } from "express";
import type { SmsDeliveryRecorder } from "./sms-delivery-recorder.js";

/**
 * SMS delivery callbacks (DLR/events).
 *
 * Route shapes (kept provider-specific inside this router):
 * - BulkSMS Nigeria: POST /bulksms with JSON containing the message_id the
 *   send response returned. BulkSMS documents delivery callbacks via the
 *   callback_url send parameter; the callback carries per-recipient status
 *   ("delivrd", "sent awaiting status", "failed"/"undeliv", etc. — the same
 *   vocabulary as the GET /api/v2/delivery-reports endpoint).
 * - Termii: POST /termii with a signed JSON event. Termii authenticates its
 *   webhook with the account webhook secret; we require the exact secret in
 *   the X-Termii-Signature header (constant-time compare), matching the
 *   convention used across our payment webhooks. Events are only accepted
 *   when TERMII_WEBHOOK_SECRET is configured — the flow is opt-in.
 *
 * Security model:
 * - BulkSMS has no HMAC signing on its DLR callbacks; anyone who can guess
 *   the URL can post to it. Therefore the endpoint only ever downgrades an
 *   attempt to a worse state it already claims (failed) or upgrades an
 *   unknown to provider-claimed status; it can NEVER touch financial state,
 *   OTP challenges, or user data. Payload validation + challenge-id lookup
 *   bound the impact of forged callbacks to the SMS delivery ledger.
 * - Termii events are HMAC-verified when the secret is configured; requests
 *   with an invalid signature are rejected 401 before parsing.
 */
export function createSmsCallbackRouter(recorder: SmsDeliveryRecorder): Router {
  const router = Router();

  router.post("/bulksms", async (req, res, next) => {
    try {
      const body = req.body as Record<string, unknown> | undefined;
      if (!body || typeof body !== "object") throw new Error("SMS_CALLBACK_INVALID");

      // Accept either a single event object or a delivery-report array item.
      const messageId = firstString(body, ["message_id", "messageId"]);
      const recipient = firstString(body, ["recipient", "to", "msisdn"]);
      const status = firstString(body, ["delivery_status", "status", "dlr_status"]);
      if (!messageId || typeof messageId !== "string" || messageId.length > 128) {
        throw new Error("SMS_CALLBACK_INVALID");
      }

      await recorder.recordDelivery({
        provider: "bulksms",
        providerMessageId: messageId,
        recipient: recipient && typeof recipient === "string" ? recipient.slice(0, 32) : undefined,
        status: mapBulkSmsStatus(status)
      });
      // Always 200: DLR endpoints must not leak whether an id exists.
      res.status(200).json({ ok: true });
    } catch (e) { next(e); }
  });

  router.post("/termii", async (req, res, next) => {
    try {
      if (!recorder.verifyTermiiWebhook((req as any).rawBody as Buffer | undefined, req.header("x-termii-signature") ?? undefined)) {
        // Signature failure is an auth failure, not a validation failure.
        throw new Error("SMS_CALLBACK_UNAUTHORIZED");
      }
      const body = req.body as Record<string, unknown> | undefined;
      if (!body || typeof body !== "object") throw new Error("SMS_CALLBACK_INVALID");

      const messageId = firstString(body, ["message_id", "messageId", "id"]);
      const status = firstString(body, ["status"]);
      if (!messageId || typeof messageId !== "string" || messageId.length > 128) {
        throw new Error("SMS_CALLBACK_INVALID");
      }

      await recorder.recordDelivery({
        provider: "termii",
        providerMessageId: messageId,
        recipient: firstString(body, ["receiver"])?.slice(0, 32),
        status: mapTermiiStatus(status)
      });
      res.status(200).json({ ok: true });
    } catch (e) { next(e); }
  });

  return router;
}

function firstString(body: Record<string, unknown>, keys: string[]): string | undefined {
  for (const key of keys) {
    const value = body[key];
    if (typeof value === "string" && value.length > 0) return value;
  }
  return undefined;
}

/** BulkSMS DLR vocabulary -> normalized delivery status. Unknown stays unknown. */
function mapBulkSmsStatus(status: string | undefined): "delivered" | "failed" | "unknown" {
  switch (status) {
    case "delivrd":
    case "delivered":
      return "delivered";
    case "undeliv":
    case "failed":
    case "rejected":
    case "expired":
      return "failed";
    default:
      return "unknown";
  }
}

/** Termii event vocabulary -> normalized delivery status. */
function mapTermiiStatus(status: string | undefined): "delivered" | "failed" | "submitted" | "unknown" {
  switch (status) {
    case "Delivered":
      return "delivered";
    case "Failed":
    case "Rejected":
      return "failed";
    case "Message sent":
    case "Sending":
    case "Submitted":
      return "submitted";
    default:
      return "unknown";
  }
}
