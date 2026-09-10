import { randomUUID } from "node:crypto";
import type { PaymentProvider } from "./payment-provider.js";
import type { PaymentRepository } from "./payment-repository.js";
import { evaluatePaymentRisk } from "./payment-risk.js";
import type { SensitiveAuthorization, AuthorizationProof } from "../security/sensitive-authorization.js";
import type { RiskService } from "../risk/risk-service.js";

/**
 * Webhook event names that MAY carry a completed charge. Anything else is
 * acknowledged without state mutation. Event names are a fast-path filter —
 * server-side verification (provider.verify) remains the sole authority for
 * settlement.
 */
const SETTLE_EVENTS: Record<"paystack" | "flutterwave", Set<string>> = {
  paystack: new Set(["charge.success"]),
  flutterwave: new Set(["charge.completed", "payment.completed"])
};

export class PaymentService {
  constructor(
    private readonly repo: PaymentRepository,
    private readonly providers: Record<"paystack" | "flutterwave", PaymentProvider>,
    private readonly authorization?: SensitiveAuthorization,
    private readonly risk?: RiskService
  ) {}

  async initialize(input: { userId: string; provider: "paystack" | "flutterwave"; amountMinor: number; email: string; callbackUrl?: string }) {
    if (!Number.isSafeInteger(input.amountMinor) || input.amountMinor <= 0) throw Error("PAYMENT_AMOUNT_INVALID");
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(input.email)) throw Error("PAYMENT_EMAIL_INVALID");
    const provider = this.providers[input.provider];
    if (!provider) throw Error("PAYMENT_PROVIDER_UNAVAILABLE");
    const reference = "OPPA_" + Date.now() + "_" + randomUUID().replaceAll("-", "");
    // userId rides as provider metadata for support reconciliation only —
    // settlement validation NEVER trusts it (webhook ownership is resolved
    // from our own database row, keyed by provider + reference).
    const result = await provider.initialize({
      amountMinor: input.amountMinor,
      email: input.email,
      reference,
      callbackUrl: input.callbackUrl,
      metadata: { userId: input.userId }
    });
    return this.repo.create({ userId: input.userId, provider: input.provider, reference, amountMinor: input.amountMinor, authorizationUrl: result.authorizationUrl });
  }

  async authorizeReversal(userId: string, proof: AuthorizationProof) {
    if (!this.authorization) throw Error("SENSITIVE_AUTH_UNAVAILABLE");
    return this.authorization.authorize({ userId, operation: "payment_reversal", proof });
  }

  async reverse(userId: string, paymentId: string, proof: AuthorizationProof, reason: string) {
    if (!paymentId || paymentId.length > 128) throw Error("PAYMENT_NOT_FOUND");
    if (!reason || reason.length > 500) throw Error("PAYMENT_REVERSAL_REASON_INVALID");
    const payment = await this.repo.findById(userId, paymentId);
    if (!payment) throw Error("PAYMENT_NOT_FOUND");
    if (!this.authorization) throw Error("SENSITIVE_AUTH_UNAVAILABLE");
    const intent = { paymentId: payment.id, reference: payment.reference, amountMinor: payment.amountMinor, currency: payment.currency };
    await this.authorization.authorize({ userId, operation: "payment_reversal", proof, intent });
    return this.repo.reverseAndDebit({ paymentId: payment.id, reason });
  }

  async handleWebhook(providerName: "paystack" | "flutterwave", rawBody: Buffer, signature: string | undefined) {
    // 1. Authenticity: signature over the RAW body, constant-time compare.
    const provider = this.providers[providerName];
    if (!provider || !provider.verifyWebhook(rawBody, signature)) throw Error("PAYMENT_WEBHOOK_INVALID");

    // 2. Parse + reference extraction with strict shape validation.
    let body: any;
    try { body = JSON.parse(rawBody.toString("utf8")); } catch { throw Error("PAYMENT_WEBHOOK_INVALID"); }
    const reference = providerName === "paystack" ? body?.data?.reference : body?.data?.tx_ref;
    if (typeof reference !== "string" || !/^[A-Za-z0-9._:-]{1,160}$/.test(reference)) throw Error("PAYMENT_REFERENCE_INVALID");

    // 3. Event gate: signed but non-settlement events are acknowledged with
    //    zero state mutation (e.g. transfer events, refund updates).
    const event = typeof body?.event === "string" ? body.event : undefined;
    if (event && !SETTLE_EVENTS[providerName].has(event)) return { status: "ignored" };

    // 4. Server-side verification. Provider failure/timeout throws (fail
    //    closed) so the provider redelivers; webhook data alone never settles.
    const verified = await provider.verify(reference);
    if (verified.reference !== reference) throw Error("PAYMENT_REFERENCE_MISMATCH");
    if (verified.currency !== "NGN") throw Error("PAYMENT_CURRENCY_INVALID");
    if (!Number.isSafeInteger(verified.amountMinor) || verified.amountMinor <= 0) throw Error("PAYMENT_AMOUNT_INVALID");

    // 5. Resolve the OPPA transaction from OUR database (never from the
    //    webhook payload — ownership comes from the row's user_id).
    const existing = await this.repo.findByProviderReference(providerName, reference);
    if (!existing) throw Error("PAYMENT_NOT_FOUND");

    if (verified.status !== "success") {
      // pending: transaction not final — persist nothing, ask provider to
      // redeliver the terminal event later. Never mark failed on pending.
      if (verified.status === "pending") return { status: "pending" };
      // failed/abandoned: close the pending row honestly. A later
      // provider-verified success can still settle it (markPaidAndCredit
      // accepts failed->paid as a reconciliation path).
      await this.repo.markFailed(providerName, reference);
      return { status: "failed" };
    }

    // 6. Idempotency / replay: an already-paid row short-circuits in
    //    markPaidAndCredit without a second credit; early-return keeps it
    //    explicit for replays that race after settlement.
    if (existing.status === "paid") return { status: "paid", payment: existing };

    // 7. Amount/currency agreement between provider and our recorded intent.
    if (existing.amountMinor !== verified.amountMinor || existing.currency !== "NGN") {
      throw Error("PAYMENT_AMOUNT_MISMATCH");
    }

    // 8. Risk gates (operator decision first, then adaptive heuristics).
    if (this.risk) {
      const decision = await this.risk.getActiveDecision(existing.userId, "payment");
      if (decision === "block") {
        await this.risk.recordEvent({
          userId: existing.userId, category: "payment_anomaly", signal: "operator_block",
          score: 100, decision: "block", reasons: ["Operator payment block active"],
          metadata: { provider: providerName, reference }
        });
        throw Error("PAYMENT_RISK_BLOCKED");
      }
      if (decision === "review") {
        await this.risk.recordEvent({
          userId: existing.userId, category: "payment_anomaly", signal: "operator_review",
          score: 60, decision: "review", reasons: ["Operator payment review active"],
          metadata: { provider: providerName, reference }
        });
        throw Error("PAYMENT_REQUIRES_REVIEW");
      }
    }
    const counts = await this.repo.countRecent(existing.userId, new Date(Date.now() - 24 * 60 * 60 * 1000));
    const evaluated = evaluatePaymentRisk({ amountMinor: verified.amountMinor, recentPaidCount: counts.paid, recentFailedCount: counts.failed });
    await this.repo.setRisk(existing.id, evaluated.score, evaluated.decision, evaluated.reasons);
    if (evaluated.decision !== "allow") {
      await this.risk?.recordEvent({
        userId: existing.userId, category: "payment_anomaly",
        signal: evaluated.decision === "block" ? "risk_blocked" : "risk_review",
        score: evaluated.score, decision: evaluated.decision, reasons: evaluated.reasons,
        metadata: { provider: providerName, reference, amountMinor: verified.amountMinor }
      });
      throw Error(evaluated.decision === "block" ? "PAYMENT_RISK_BLOCKED" : "PAYMENT_REQUIRES_REVIEW");
    }

    // 9. Financial settlement: single DB transaction (row lock, wallet credit,
    //    double-entry reference, audit, outbox) inside the repository.
    const payment = await this.repo.markPaidAndCredit({
      provider: providerName, reference, transactionId: verified.transactionId, amountMinor: verified.amountMinor
    });
    return { status: "paid", payment };
  }
}
