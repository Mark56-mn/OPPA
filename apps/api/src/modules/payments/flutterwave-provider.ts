import { timingSafeEqual } from "node:crypto";
import type {
  PaymentProvider,
  PaymentProviderOptions,
  VerifiedPayment,
  VerifiedPaymentStatus
} from "./payment-provider.js";

const DEFAULT_BASE = "https://api.flutterwave.com/v3";

/**
 * Flutterwave V3 adapter (deliberately V3 — not V4/OAuth).
 *
 * - Webhook authentication: Flutterwave V3 sends the webhook secret verbatim
 *   in the `verif-hash` header; compare with the configured
 *   FLUTTERWAVE_WEBHOOK_SECRET in constant time.
 * - Verification: GET /transactions/verify_by_reference?tx_ref=... server-side
 *   (webhook data alone is never trusted for settlement).
 * - Amounts: Flutterwave returns major units; normalize to minor (kobo) here.
 * - FLUTTERWAVE_ENCRYPTION_KEY is only used by V3 endpoints that require it
 *   (e.g. charge payloads); the initialize/verify surface below does not need
 *   it, so it is accepted and reserved — never logged.
 */
export class FlutterwaveProvider implements PaymentProvider {
  readonly name = "flutterwave" as const;

  constructor(
    private readonly secret: string,
    private readonly webhookSecret: string,
    private readonly options?: PaymentProviderOptions
  ) {}

  private base(): string {
    return (this.options?.baseUrl ?? DEFAULT_BASE).replace(/\/+$/, "");
  }

  private headers() {
    return { Authorization: `Bearer ${this.secret}`, "Content-Type": "application/json" };
  }

  async initialize(input: { amountMinor: number; email: string; reference: string; callbackUrl?: string }) {
    const response = await fetch(`${this.base()}/payments`, {
      method: "POST",
      headers: this.headers(),
      body: JSON.stringify({
        tx_ref: input.reference,
        amount: input.amountMinor / 100,
        currency: "NGN",
        ...(input.callbackUrl ? { redirect_url: input.callbackUrl } : {}),
        customer: { email: input.email }
      })
    });
    const data: any = await response.json().catch(() => null);
    if (!response.ok || data?.status !== "success" || !data.data?.link) {
      throw new Error("PAYMENT_PROVIDER_ERROR");
    }
    return { authorizationUrl: String(data.data.link) };
  }

  async verify(reference: string): Promise<VerifiedPayment> {
    const response = await fetch(
      `${this.base()}/transactions/verify_by_reference?tx_ref=${encodeURIComponent(reference)}`,
      { headers: this.headers() }
    );
    const data: any = await response.json().catch(() => null);
    if (!response.ok || data?.status !== "success" || !data.data) throw new Error("PAYMENT_PROVIDER_ERROR");
    const p = data.data;
    return {
      reference: String(p.tx_ref),
      transactionId: String(p.id),
      amountMinor: Math.round(Number(p.amount) * 100),
      currency: p.currency === "NGN" ? "NGN" : (() => { throw new Error("PAYMENT_CURRENCY_INVALID"); })(),
      status: mapFlutterwaveStatus(p.status)
    };
  }

  verifyWebhook(_rawBody: Buffer, signature?: string) {
    if (!signature) return false;
    const a = Buffer.from(this.webhookSecret, "utf8");
    const b = Buffer.from(signature, "utf8");
    return a.length === b.length && timingSafeEqual(a, b);
  }
}

/** Map Flutterwave V3 status; unknown strings never become success. */
function mapFlutterwaveStatus(status: unknown): VerifiedPaymentStatus {
  switch (status) {
    case "successful":
      return "success";
    case "failed":
    case "cancelled":
    case "error":
      return "failed";
    case "pending":
    case "processing":
    case "new":
      return "pending";
    case "abandoned":
      return "abandoned";
    default:
      return "pending";
  }
}
