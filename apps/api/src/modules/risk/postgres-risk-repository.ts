import { db } from "../../db/pool.js";
import type {
  RiskDecisionInput, RiskEventInput, RiskDecision, RiskDecisionRecord, RiskEventRecord,
  RiskRepository, RiskScope, TransferCounters, WalletLimits
} from "./risk-repository.js";

function requireDb() { if (!db) throw new Error("DATABASE_URL is not configured"); return db; }

export class PostgresRiskRepository implements RiskRepository {
  async recordEvent(input: RiskEventInput) {
    await requireDb().query(
      `insert into public.oppa_risk_events(user_id,device_id,category,signal,score,decision,reasons,metadata)
       values($1,$2,$3,$4,$5,$6,$7::jsonb,$8::jsonb)`,
      [input.userId ?? null, input.deviceId ?? null, input.category, input.signal,
       input.score ?? 0, input.decision ?? "allow",
       JSON.stringify(input.reasons ?? []), JSON.stringify(input.metadata ?? {})]
    );
  }

  async createDecision(input: RiskDecisionInput) {
    await requireDb().query(
      `insert into public.oppa_risk_decisions(user_id,scope,decision,reason,expires_at,created_by)
       values($1,$2,$3,$4,$5,$6)`,
      [input.userId, input.scope, input.decision, input.reason, input.expiresAt ?? null, input.createdBy ?? null]
    );
  }

  async getActiveDecision(userId: string, scope: RiskScope): Promise<RiskDecision | null> {
    const r = await requireDb().query(
      `select decision from public.oppa_risk_decisions
       where user_id=$1 and scope=$2 and (expires_at is null or expires_at>now())
       order by created_at desc limit 1`,
      [userId, scope]
    );
    return r.rows[0]?.decision ?? null;
  }

  async listDecisions(userId: string, limit: number): Promise<RiskDecisionRecord[]> {
    const r = await requireDb().query(
      `select id,user_id as "userId",scope,decision,reason,expires_at as "expiresAt",created_at as "createdAt"
       from public.oppa_risk_decisions where user_id=$1 order by created_at desc limit $2`,
      [userId, limit]
    );
    return r.rows.map((row) => ({ ...row, expiresAt: row.expiresAt ?? null }));
  }

  async listRecentEvents(userId: string, limit: number): Promise<RiskEventRecord[]> {
    const r = await requireDb().query(
      `select id,user_id as "userId",category,signal,score,decision,reasons,created_at as "createdAt"
       from public.oppa_risk_events where user_id=$1 order by created_at desc limit $2`,
      [userId, limit]
    );
    return r.rows;
  }

  async getOrCreateWalletLimits(userId: string): Promise<WalletLimits> {
    const d = requireDb();
    await d.query("insert into public.oppa_wallet_limits(user_id) values($1) on conflict(user_id) do nothing", [userId]);
    const r = await d.query(
      `select max_single_transfer_minor as "maxSingleTransferMinor",
              max_daily_total_minor as "maxDailyTotalMinor",
              max_daily_count as "maxDailyCount"
       from public.oppa_wallet_limits where user_id=$1`,
      [userId]
    );
    const row = r.rows[0];
    return {
      maxSingleTransferMinor: Number(row.maxSingleTransferMinor),
      maxDailyTotalMinor: Number(row.maxDailyTotalMinor),
      maxDailyCount: Number(row.maxDailyCount)
    };
  }

  async getTransferCounters(userId: string, day: Date): Promise<TransferCounters> {
    const r = await requireDb().query(
      `select total_minor as "totalMinor", count from public.oppa_wallet_daily_counters
       where user_id=$1 and day=$2`,
      [userId, day.toISOString().slice(0, 10)]
    );
    const row = r.rows[0];
    return row ? { totalMinor: Number(row.totalMinor), count: Number(row.count) } : { totalMinor: 0, count: 0 };
  }

  async incrementTransferCounters(userId: string, day: Date, amountMinor: number) {
    await requireDb().query(
      `insert into public.oppa_wallet_daily_counters(user_id,day,total_minor,count)
       values($1,$2,$3,1)
       on conflict(user_id,day) do update set
         total_minor=oppa_wallet_daily_counters.total_minor+excluded.total_minor,
         count=oppa_wallet_daily_counters.count+1,
         updated_at=now()`,
      [userId, day.toISOString().slice(0, 10), amountMinor]
    );
  }
}