import { timingSafeEqual } from "node:crypto";
import type { PaymentProvider, VerifiedPayment } from "./payment-provider.js";

const BASE = "https://api.flutterwave.com/v3";

export class FlutterwaveProvider implements PaymentProvider {
  readonly name = "flutterwave" as const;
  constructor(private readonly secret: string, private readonly webhookSecret: string) {}

  private headers() { return { Authorization: `Bearer ${this.secret}`, "Content-Type": "application/json" }; }

  async initialize(input: { amountMinor: number; email: string; reference: string; callbackUrl?: string }) {
    const response = await fetch(`${BASE}/payments`, {
      method: "POST", headers: this.headers(),
      body: JSON.stringify({ tx_ref: input.reference, amount: input.amountMinor / 100, currency: "NGN", redirect_url: input.callbackUrl, customer: { email: input.email } })
    });
    const data: any = await response.json();
    if (!response.ok || data.status !== "success" || !data.data?.link) throw new Error("PAYMENT_PROVIDER_ERROR");
    return { authorizationUrl: data.data.link as string };
  }

  async verify(reference: string): Promise<VerifiedPayment> {
    const response = await fetch(`${BASE}/transactions/verify_by_reference?tx_ref=${encodeURIComponent(reference)}`, { headers: this.headers() });
    const data: any = await response.json();
    if (!response.ok || data.status !== "success" || !data.data) throw new Error("PAYMENT_PROVIDER_ERROR");
    const p = data.data;
    return {
      reference: String(p.tx_ref),
      transactionId: String(p.id),
      amountMinor: Math.round(Number(p.amount) * 100),
      currency: p.currency === "NGN" ? "NGN" : (() => { throw new Error("PAYMENT_CURRENCY_INVALID"); })(),
      status: p.status === "successful" ? "success" : "failed"
    };
  }

  verifyWebhook(_rawBody: Buffer, signature?: string) {
    if (!signature) return false;
    const a = Buffer.from(this.webhookSecret, "utf8"), b = Buffer.from(signature, "utf8");
    return a.length === b.length && timingSafeEqual(a, b);
  }
}
