export type PaymentProviderName = "paystack" | "flutterwave";

/**
 * Provider transaction status, normalized without collapsing unknown states
 * into success or failure. `pending`/`abandoned` stay distinct so the service
 * can act honestly: pending = wait, abandoned = provider says the checkout was
 * never completed (only safe because a later provider-verified success with a
 * different transaction id re-fails the row rather than mutating a paid one).
 */
export type VerifiedPaymentStatus = "success" | "failed" | "pending" | "abandoned";

export interface VerifiedPayment {
  reference: string;
  transactionId: string;
  amountMinor: number;
  currency: "NGN";
  status: VerifiedPaymentStatus;
}

export interface PaymentInitializeInput {
  amountMinor: number;
  email: string;
  reference: string;
  callbackUrl?: string;
  metadata?: Record<string, unknown>;
}

export interface PaymentProviderOptions {
  baseUrl?: string;
  encryptionKey?: string;
}

export interface PaymentProvider {
  readonly name: PaymentProviderName;
  initialize(input: PaymentInitializeInput): Promise<{ authorizationUrl: string }>;
  verify(reference: string): Promise<VerifiedPayment>;
  verifyWebhook(rawBody: Buffer, signature: string | undefined): boolean;
}
