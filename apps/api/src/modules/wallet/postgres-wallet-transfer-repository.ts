import { db } from "../../db/pool.js";
import { randomUUID } from "node:crypto";
import type { WalletTransferRepository, WalletTransferResult } from "./wallet-transfer-repository.js";
import type { RiskRepository } from "../risk/risk-repository.js";
import { assessTransferLimits } from "../risk/transfer-limits.js";

// Durable notification outbox: enqueue in the SAME transaction as the money
// movement so a notification exists if and only if the transfer committed.
const TRANSFER_OUTBOX_SQL = `
  insert into public.oppa_notification_outbox(event_type,user_id,dedupe_key,payload)
  values('wallet.transfer.completed',$1,$2,$3::jsonb)
  on conflict (dedupe_key) where dedupe_key is not null do nothing`;

function requireDb() {
  if (!db) throw new Error("DATABASE_URL is not configured");
  return db;
}

export class PostgresWalletTransferRepository implements WalletTransferRepository {
  constructor(private readonly risk?: RiskRepository) {}

  async transfer(input: { fromUserId: string; toUserId: string; amountMinor: number; reference: string }): Promise<WalletTransferResult> {
    if (input.fromUserId === input.toUserId) throw new Error("WALLET_TRANSFER_SELF");
    if (!Number.isSafeInteger(input.amountMinor) || input.amountMinor <= 0) throw new Error("WALLET_AMOUNT_INVALID");
    if (!/^[A-Za-z0-9._:-]{1,160}$/.test(input.reference)) throw new Error("WALLET_REFERENCE_INVALID");

    const client = await requireDb().connect();
    try {
      await client.query("begin");
      const existing = await client.query(
        'select id, reference, from_user_id as "fromUserId", to_user_id as "toUserId", amount_minor as "amountMinor", currency, status, created_at as "createdAt" from public.oppa_wallet_transfers where reference = $1 limit 1',
        [input.reference]
      );
      if (existing.rows[0]) {
        const prior = existing.rows[0];
        if (prior.fromUserId !== input.fromUserId || prior.toUserId !== input.toUserId || Number(prior.amountMinor) !== input.amountMinor) {
          throw new Error("WALLET_REFERENCE_REUSED");
        }
        await client.query("commit");
        return { ...prior, amountMinor: Number(prior.amountMinor) };
      }

      // Fail closed on operator-issued blocks before moving money.
      if (this.risk) {
        const userDecision = await this.risk.getActiveDecision(input.fromUserId, "user");
        const transferDecision = await this.risk.getActiveDecision(input.fromUserId, "transfer");
        if (userDecision === "block" || transferDecision === "block") {
          throw new Error("WALLET_TRANSFER_BLOCKED");
        }
      }

      const ordered = [input.fromUserId, input.toUserId].sort();
      await client.query(
        "insert into public.oppa_wallets (user_id, currency) values ($1,'NGN'),($2,'NGN') on conflict (user_id) do nothing",
        ordered
      );
      const locked = await client.query(
        "select user_id from public.oppa_wallets where user_id in ($1,$2) order by user_id for update",
        [ordered[0], ordered[1]]
      );
      if (locked.rowCount !== 2) throw new Error("USER_NOT_FOUND");

      // Transfer limits are enforced with the same transaction that moves
      // money, so counters can never race the debit.
      if (this.risk) {
        const limits = await this.risk.getOrCreateWalletLimits(input.fromUserId);
        const counters = await this.risk.getTransferCounters(input.fromUserId, new Date());
        const assessment = assessTransferLimits(limits, counters, input.amountMinor);
        if (!assessment.allowed) {
          const err = new Error("WALLET_TRANSFER_LIMIT_EXCEEDED") as Error & { limitReason?: string };
          err.limitReason = assessment.reason ?? undefined;
          throw err;
        }
      }

      const debit = await client.query(
        "update public.oppa_wallets set balance_minor = balance_minor - $2::bigint, updated_at = now() where user_id = $1 and balance_minor >= $2::bigint returning balance_minor",
        [input.fromUserId, input.amountMinor]
      );
      if (!debit.rows[0]) throw new Error("WALLET_INSUFFICIENT_FUNDS");

      await client.query(
        "update public.oppa_wallets set balance_minor = balance_minor + $2::bigint, updated_at = now() where user_id = $1",
        [input.toUserId, input.amountMinor]
      );

      const transferId = randomUUID();
      const created = await client.query(
        'insert into public.oppa_wallet_transfers (id,reference,from_user_id,to_user_id,amount_minor,currency,status) values ($1,$2,$3,$4,$5,\'NGN\',\'completed\') returning id, reference, from_user_id as "fromUserId", to_user_id as "toUserId", amount_minor as "amountMinor", currency, status, created_at as "createdAt"',
        [transferId, input.reference, input.fromUserId, input.toUserId, input.amountMinor]
      );
      await client.query(
        "insert into public.oppa_wallet_ledger_entries (transfer_id,user_id,entry_type,amount_minor) values ($1,$2,'debit',$3),($1,$4,'credit',$3)",
        [transferId, input.fromUserId, input.amountMinor, input.toUserId]
      );
      await client.query(
        "insert into public.oppa_audit_events(actor_user_id,event_type,entity_type,entity_id,metadata) values($1,'wallet.transfer.created','transfer',$2,$3::jsonb)",
        [input.fromUserId, transferId, JSON.stringify({ toUserId: input.toUserId, amountMinor: input.amountMinor, reference: input.reference })]
      );
      await this.risk?.incrementTransferCounters(input.fromUserId, new Date(), input.amountMinor);
      // Notification payloads carry no amounts/references beyond the opaque
      // transfer id — never expose financial detail in notification bodies.
      await client.query(TRANSFER_OUTBOX_SQL, [
        input.toUserId,
        `wallet_transfer_received:${transferId}`,
        JSON.stringify({ category: "wallet", title: "Money received", body: "You have received a transfer on OPPA", metadata: { transferId } })
      ]);
      await client.query(TRANSFER_OUTBOX_SQL, [
        input.fromUserId,
        `wallet_transfer_sent:${transferId}`,
        JSON.stringify({ category: "wallet", title: "Transfer sent", body: "Your transfer was completed", metadata: { transferId } })
      ]);
      await client.query("commit");
      const row = created.rows[0];
      return { ...row, amountMinor: Number(row.amountMinor) };
    } catch (e) {
      try { await client.query("rollback"); } catch {}
      const message = e instanceof Error ? e.message : "";
      // Record risk signals outside the rolled-back transaction so the
      // evidence survives the failed transfer.
      const limitReason = e instanceof Error ? (e as Error & { limitReason?: string }).limitReason : undefined;
      if (this.risk && (message === "WALLET_TRANSFER_LIMIT_EXCEEDED" || message === "WALLET_TRANSFER_BLOCKED")) {
        try {
          await this.risk.recordEvent({
            userId: input.fromUserId,
            category: "transfer_velocity",
            signal: message === "WALLET_TRANSFER_BLOCKED" ? "operator_block" : "limit_exceeded",
            score: 100,
            decision: "block",
            reasons: [limitReason ?? message],
            metadata: { toUserId: input.toUserId, amountMinor: input.amountMinor, reference: input.reference }
          });
        } catch {}
      }
      throw e;
    } finally {
      client.release();
    }
  }
}