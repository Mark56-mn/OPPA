export type PaymentRecord = {
  id: string; userId: string; provider: "paystack" | "flutterwave"; reference: string;
  providerTransactionId: string | null; amountMinor: number; currency: "NGN";
  status: "pending" | "paid" | "failed" | "reversed"; authorizationUrl: string | null;
};

export interface PaymentRepository {
  create(input: { userId: string; provider: "paystack" | "flutterwave"; reference: string; amountMinor: number; authorizationUrl: string }): Promise<PaymentRecord>;
  find(userId: string, reference: string): Promise<PaymentRecord | null>;
  markPaidAndCredit(input: { provider: "paystack" | "flutterwave"; reference: string; transactionId: string; amountMinor: number }): Promise<PaymentRecord>;
  markFailed(provider: "paystack" | "flutterwave", reference: string): Promise<void>;
}
