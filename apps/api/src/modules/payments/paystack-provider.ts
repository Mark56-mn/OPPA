import { createHmac, timingSafeEqual } from "node:crypto";
import type {
  PaymentProvider,
  PaymentProviderOptions,
  VerifiedPayment,
  VerifiedPaymentStatus
} from "./payment-provider.js";

const DEFAULT_BASE = "https://api.paystack.co";

/**
 * Paystack adapter.
 *
 * - Webhook signature: HMAC-SHA512 hex of the RAW request body keyed with the
 *   SECRET KEY, in the `x-paystack-signature` header. This is Paystack's
 *   documented mechanism — no separate webhook secret exists, so the task's
 *   "no separate Paystack webhook secret unless required" rule holds.
 * - Amounts: Paystack returns minor units already (kobo). No conversion.
 * - Timeout semantics: verification failures throw PAYMENT_PROVIDER_ERROR so
 *   the webhook handler fails closed (provider can redeliver); we never guess.
 */
export class PaystackProvider implements PaymentProvider {
  readonly name = "paystack" as const;

  constructor(
    private readonly secret: string,
    private readonly options?: PaymentProviderOptions
  ) {}

  private base(): string {
    return (this.options?.baseUrl ?? DEFAULT_BASE).replace(/\/+$/, "");
  }

  private headers() {
    return { Authorization: `Bearer ${this.secret}`, "Content-Type": "application/json" };
  }

  async initialize(input: { amountMinor: number; email: string; reference: string; callbackUrl?: string }) {
    const response = await fetch(`${this.base()}/transaction/initialize`, {
      method: "POST",
      headers: this.headers(),
      body: JSON.stringify({
        amount: input.amountMinor,
        email: input.email,
        reference: input.reference,
        ...(input.callbackUrl ? { callback_url: input.callbackUrl } : {})
      })
    });
    const data: any = await response.json().catch(() => null);
    if (!response.ok || !data?.status || !data.data?.authorization_url) {
      throw new Error("PAYMENT_PROVIDER_ERROR");
    }
    return { authorizationUrl: String(data.data.authorization_url) };
  }

  async verify(reference: string): Promise<VerifiedPayment> {
    const response = await fetch(`${this.base()}/transaction/verify/${encodeURIComponent(reference)}`, {
      headers: this.headers()
    });
    const data: any = await response.json().catch(() => null);
    if (!response.ok || !data?.status || !data.data) throw new Error("PAYMENT_PROVIDER_ERROR");
    const p = data.data;
    return {
      reference: String(p.reference),
      transactionId: String(p.id),
      amountMinor: Number(p.amount),
      currency: p.currency === "NGN" ? "NGN" : (() => { throw new Error("PAYMENT_CURRENCY_INVALID"); })(),
      status: mapPaystackStatus(p.status)
    };
  }

  verifyWebhook(rawBody: Buffer, signature?: string) {
    if (!signature) return false;
    const expected = createHmac("sha512", this.secret).update(rawBody).digest("hex");
    const a = Buffer.from(expected, "utf8");
    const b = Buffer.from(signature, "utf8");
    return a.length === b.length && timingSafeEqual(a, b);
  }
}

/** Map Paystack transaction status; unknown strings never become success. */
function mapPaystackStatus(status: unknown): VerifiedPaymentStatus {
  switch (status) {
    case "success":
      return "success";
    case "failed":
    case "reversed":
      return "failed";
    case "ongoing":
      return "pending";
    case "abandoned":
      return "abandoned";
    default:
      return "failed";
  }
}
