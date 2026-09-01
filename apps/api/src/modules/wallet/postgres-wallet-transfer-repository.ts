import { db } from "../../db/pool.js";
import { randomUUID } from "node:crypto";
import type { WalletTransferRepository, WalletTransferResult } from "./wallet-transfer-repository.js";

function requireDb() {
  if (!db) throw new Error("DATABASE_URL is not configured");
  return db;
}

export class PostgresWalletTransferRepository implements WalletTransferRepository {
  async transfer(input: {
    fromUserId: string;
    toUserId: string;
    amountMinor: number;
    reference: string;
  }): Promise<WalletTransferResult> {
    if (input.fromUserId === input.toUserId) throw new Error("WALLET_TRANSFER_SELF");
    if (!Number.isSafeInteger(input.amountMinor) || input.amountMinor <= 0) throw new Error("WALLET_AMOUNT_INVALID");
    if (!input.reference || input.reference.length > 160) throw new Error("WALLET_REFERENCE_INVALID");

    const client = await requireDb().connect();
    try {
      await client.query("begin");

      const existing = await client.query(
        `select id, reference, from_user_id as "fromUserId", to_user_id as "toUserId",
                amount_minor as "amountMinor", currency, status, created_at as "createdAt"
         from public.oppa_wallet_transfers where reference = $1 limit 1`,
        [input.reference]
      );
      if (existing.rows[0]) {
        const prior = existing.rows[0];
        if (prior.fromUserId !== input.fromUserId || prior.toUserId !== input.toUserId ||
            Number(prior.amountMinor) !== input.amountMinor) {
          throw new Error("WALLET_REFERENCE_REUSED");
        }
        await client.query("commit");
        return { ...prior, amountMinor: Number(prior.amountMinor) };
      }

      // Lock both wallets in deterministic order to prevent deadlocks.
      const ordered = [input.fromUserId, input.toUserId].sort();
      await client.query(
        `insert into public.oppa_wallets (user_id, currency)
         values ($1,'NGN'),($2,'NGN')
         on conflict (user_id) do nothing`,
        ordered
      );

      const locked = await client.query(
        `select user_id from public.oppa_wallets
         where user_id in ($1,$2) order by user_id for update`,
        [ordered[0], ordered[1]]
      );
      if (locked.rowCount !== 2) throw new Error("USER_NOT_FOUND");

      const debit = await client.query(
        `update public.oppa_wallets
         set balance_minor = balance_minor - $2::bigint, updated_at = now()
         where user_id = $1 and balance_minor >= $2::bigint
         returning balance_minor`,
        [input.fromUserId, input.amountMinor]
      );
      if (!debit.rows[0]) throw new Error("WALLET_INSUFFICIENT_FUNDS");

      await client.query(
        `update public.oppa_wallets
         set balance_minor = balance_minor + $2::bigint, updated_at = now()
         where user_id = $1`,
        [input.toUserId, input.amountMinor]
      );

      const transferId = randomUUID();
      const created = await client.query(
        `insert into public.oppa_wallet_transfers
         (id,reference,from_user_id,to_user_id,amount_minor,currency,status)
         values ($1,$2,$3,$4,$5,'NGN','completed')
         returning id, reference, from_user_id as "fromUserId", to_user_id as "toUserId",
                   amount_minor as "amountMinor", currency, status, created_at as "createdAt"`,
        [transferId,input.reference,input.fromUserId,input.toUserId,input.amountMinor]
      );

      await client.query(
        `insert into public.oppa_wallet_ledger_entries
         (transfer_id,user_id,entry_type,amount_minor)
         values ($1,$2,'debit',$3),($1,$4,'credit',$3)`,
        [transferId,input.fromUserId,input.amountMinor,input.toUserId]
      );

      await client.query("commit");
      const row = created.rows[0];
      return { ...row, amountMinor: Number(row.amountMinor) };
    } catch (e: any) {
      await client.query("rollback");
      throw e;
    } finally {
      client.release();
    }
  }
}
