import { db } from "../../db/pool.js";
import type { PaymentRepository, PaymentRecord } from "./payment-repository.js";
import type { WalletRepository } from "../wallet/wallet-repository.js";

function requireDb() { if (!db) throw new Error("DATABASE_URL is not configured"); return db; }
function map(row:any): PaymentRecord { return { ...row, amountMinor: Number(row.amountMinor) }; }

export class PostgresPaymentRepository implements PaymentRepository {
  constructor(private readonly wallets: WalletRepository) {}
  async create(input:{userId:string;provider:"paystack"|"flutterwave";reference:string;amountMinor:number;authorizationUrl:string}) {
    const r=await requireDb().query(
      `insert into public.oppa_payments (user_id,provider,reference,amount_minor,currency,status,authorization_url)
       values ($1,$2,$3,$4,'NGN','pending',$5)
       on conflict (provider,reference) do update set updated_at=now()
       returning id,user_id as "userId",provider,reference,provider_transaction_id as "providerTransactionId", amount_minor as "amountMinor",currency,status,authorization_url as "authorizationUrl"`,
      [input.userId,input.provider,input.reference,input.amountMinor,input.authorizationUrl]);
    return map(r.rows[0]);
  }
  async find(userId:string,reference:string) {
    const r=await requireDb().query(`select id,user_id as "userId",provider,reference,provider_transaction_id as "providerTransactionId",amount_minor as "amountMinor",currency,status,authorization_url as "authorizationUrl" from public.oppa_payments where user_id=$1 and reference=$2 limit 1`,[userId,reference]);
    return r.rows[0] ? map(r.rows[0]) : null;
  }
  async markPaidAndCredit(input:{provider:"paystack"|"flutterwave";reference:string;transactionId:string;amountMinor:number}) {
    const client=await requireDb().connect();
    try {
      await client.query("begin");
      const r=await client.query(`select id,user_id as "userId",provider,reference,provider_transaction_id as "providerTransactionId",amount_minor as "amountMinor",currency,status,authorization_url as "authorizationUrl" from public.oppa_payments where provider=$1 and reference=$2 for update`,[input.provider,input.reference]);
      if (!r.rows[0]) throw new Error("PAYMENT_NOT_FOUND");
      const p=map(r.rows[0]);
      if (p.amountMinor!==input.amountMinor || p.currency!=="NGN") throw new Error("PAYMENT_AMOUNT_MISMATCH");
      if (p.status==="paid") { if (p.providerTransactionId && p.providerTransactionId!==input.transactionId) throw new Error("PAYMENT_TRANSACTION_MISMATCH"); await client.query("commit"); return p; }
      if (p.status==="reversed") throw new Error("PAYMENT_ALREADY_REVERSED");
      await client.query(`update public.oppa_payments set status='paid',provider_transaction_id=$2,provider_status='success',paid_at=now(),updated_at=now() where id=$1 and status='pending'`,[p.id,input.transactionId]);
      await this.wallets.credit(p.userId,p.amountMinor,`payment:${p.provider}:${p.reference}`,"Wallet funding");
      await client.query("commit");
      return { ...p, status:"paid", providerTransactionId:input.transactionId };
    } catch(e) { try { await client.query("rollback"); } catch {} throw e; }
    finally { client.release(); }
  }
  async markFailed(provider:"paystack"|"flutterwave",reference:string) { await requireDb().query(`update public.oppa_payments set status='failed',updated_at=now() where provider=$1 and reference=$2 and status='pending'`,[provider,reference]); }
}