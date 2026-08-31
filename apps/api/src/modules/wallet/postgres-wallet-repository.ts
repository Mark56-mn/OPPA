import { db } from "../../db/pool.js";
import type { Wallet, WalletRepository, WalletTransaction } from "./wallet-repository.js";

function requireDb() {
  if (!db) throw new Error("DATABASE_URL is not configured");
  return db;
}

export class PostgresWalletRepository implements WalletRepository {
  async getOrCreate(userId: string): Promise<Wallet> {
    const r = await requireDb().query(
      `insert into public.oppa_wallets (user_id, currency)
       values ($1, 'NGN')
       on conflict (user_id) do nothing
       returning user_id as "userId", currency, balance_minor as "balanceMinor", updated_at as "updatedAt"`,
      [userId]
    );
    if (r.rows[0]) return r.rows[0];
    const existing = await requireDb().query(
      `select user_id as "userId", currency, balance_minor as "balanceMinor", updated_at as "updatedAt"
       from public.oppa_wallets where user_id = $1`, [userId]
    );
    return existing.rows[0];
  }

  async listTransactions(userId: string, limit: number, before?: string) {
    const safeLimit = Math.min(Math.max(limit || 50, 1), 100);
    const r = await requireDb().query(
      `select id, user_id as "userId", type, amount_minor as "amountMinor",
              balance_after_minor as "balanceAfterMinor", reference, description,
              created_at as "createdAt"
       from public.oppa_wallet_transactions
       where user_id = $1 and ($2::timestamptz is null or created_at < $2)
       order by created_at desc limit $3`,
      [userId, before ?? null, safeLimit]
    );
    return r.rows as WalletTransaction[];
  }

  async credit(userId: string, amountMinor: number, reference: string, description?: string | null) {
    return this.mutate(userId, "credit", amountMinor, reference, description);
  }

  async debit(userId: string, amountMinor: number, reference: string, description?: string | null) {
    return this.mutate(userId, "debit", amountMinor, reference, description);
  }

  private async mutate(userId: string, type: "credit" | "debit", amountMinor: number, reference: string, description?: string | null) {
    if (!Number.isSafeInteger(amountMinor) || amountMinor <= 0) throw new Error("WALLET_AMOUNT_INVALID");
    if (!reference || reference.length > 160) throw new Error("WALLET_REFERENCE_INVALID");

    const client = await requireDb().connect();
    try {
      await client.query("begin");

      const existing = await client.query(
        `select id, user_id as "userId", type, amount_minor as "amountMinor",
                balance_after_minor as "balanceAfterMinor", reference, description,
                created_at as "createdAt"
         from public.oppa_wallet_transactions where reference = $1 for share`,
        [reference]
      );
      if (existing.rows[0]) {
        await client.query("commit");
        return existing.rows[0] as WalletTransaction;
      }

      await client.query(
        `insert into public.oppa_wallets (user_id, currency)
         values ($1, 'NGN') on conflict (user_id) do nothing`, [userId]
      );

      const delta = type === "credit" ? amountMinor : -amountMinor;
      const wallet = await client.query(
        `update public.oppa_wallets
         set balance_minor = balance_minor + $2, updated_at = now()
         where user_id = $1 and ($2 > 0 or balance_minor + $2 >= 0)
         returning balance_minor as "balanceAfterMinor"`,
        [userId, delta]
      );
      if (!wallet.rows[0]) throw new Error("WALLET_INSUFFICIENT_FUNDS");

      const tx = await client.query(
        `insert into public.oppa_wallet_transactions
         (user_id, type, amount_minor, balance_after_minor, reference, description)
         values ($1,$2,$3,$4,$5,$6)
         returning id, user_id as "userId", type, amount_minor as "amountMinor",
                   balance_after_minor as "balanceAfterMinor", reference, description,
                   created_at as "createdAt"`,
        [userId, type, amountMinor, wallet.rows[0].balanceAfterMinor, reference, description ?? null]
      );

      await client.query("commit");
      return tx.rows[0] as WalletTransaction;
    } catch (e) {
      await client.query("rollback");
      throw e;
    } finally {
      client.release();
    }
  }
}
