import { createHmac, timingSafeEqual } from "node:crypto";
import type { PaymentProvider, VerifiedPayment } from "./payment-provider.js";

const BASE = "https://api.paystack.co";

export class PaystackProvider implements PaymentProvider {
  readonly name = "paystack" as const;
  constructor(private readonly secret: string) {}

  private headers() { return { Authorization: `Bearer ${this.secret}`, "Content-Type": "application/json" }; }

  async initialize(input: { amountMinor: number; email: string; reference: string; callbackUrl?: string }) {
    const response = await fetch(`${BASE}/transaction/initialize`, {
      method: "POST", headers: this.headers(),
      body: JSON.stringify({ amount: input.amountMinor, email: input.email, reference: input.reference, callback_url: input.callbackUrl })
    });
    const data: any = await response.json();
    if (!response.ok || !data.status || !data.data?.authorization_url) throw new Error("PAYMENT_PROVIDER_ERROR");
    return { authorizationUrl: data.data.authorization_url as string };
  }

  async verify(reference: string): Promise<VerifiedPayment> {
    const response = await fetch(`${BASE}/transaction/verify/${encodeURIComponent(reference)}`, { headers: this.headers() });
    const data: any = await response.json();
    if (!response.ok || !data.status || !data.data) throw new Error("PAYMENT_PROVIDER_ERROR");
    const p = data.data;
    return {
      reference: String(p.reference),
      transactionId: String(p.id),
      amountMinor: Number(p.amount),
      currency: p.currency === "NGN" ? "NGN" : (() => { throw new Error("PAYMENT_CURRENCY_INVALID"); })(),
      status: p.status === "success" ? "success" : "failed"
    };
  }

  verifyWebhook(rawBody: Buffer, signature?: string) {
    if (!signature) return false;
    const expected = createHmac("sha512", this.secret).update(rawBody).digest("hex");
    const a = Buffer.from(expected, "utf8"), b = Buffer.from(signature, "utf8");
    return a.length === b.length && timingSafeEqual(a, b);
  }
}
