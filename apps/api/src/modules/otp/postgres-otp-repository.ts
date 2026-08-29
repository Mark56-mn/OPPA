import type { OtpChallenge, OtpRepository } from "./otp-repository.js";
import { db } from "../../db/pool.js";

function requireDb() {
  if (!db) throw new Error("DATABASE_URL is not configured");
  return db;
}

export class PostgresOtpRepository implements OtpRepository {
  async invalidateActive(phone: string, now: Date): Promise<void> {
    await requireDb().query(
      `update public.otp_challenges
       set consumed_at = $2
       where phone_e164 = $1
         and consumed_at is null
         and expires_at > $2`,
      [phone, now]
    );
  }

  async getLatestCreatedAt(phone: string): Promise<Date | null> {
    const result = await requireDb().query(
      `select created_at
       from public.otp_challenges
       where phone_e164 = $1
       order by created_at desc
       limit 1`,
      [phone]
    );
    return result.rows[0]?.created_at ?? null;
  }

  async countCreatedSince(phone: string, since: Date): Promise<number> {
    const result = await requireDb().query(
      `select count(*)::int as count
       from public.otp_challenges
       where phone_e164 = $1
         and created_at >= $2`,
      [phone, since]
    );
    return Number(result.rows[0].count);
  }

  async create(challenge: OtpChallenge): Promise<void> {
    await requireDb().query(
      `insert into public.otp_challenges
       (id, phone_e164, otp_hash, expires_at, attempts, consumed_at, provider_message_id)
       values ($1, $2, $3, $4, $5, $6, $7)`,
      [
        challenge.id,
        challenge.phone,
        challenge.otpHash,
        challenge.expiresAt,
        challenge.attempts,
        challenge.consumedAt,
        challenge.providerMessageId
      ]
    );
  }

  async setProviderMessageId(id: string, providerMessageId: string): Promise<void> {
    await requireDb().query(
      `update public.otp_challenges
       set provider_message_id = $2
       where id = $1`,
      [id, providerMessageId]
    );
  }

  async getActive(phone: string, now: Date): Promise<OtpChallenge | null> {
    const result = await requireDb().query(
      `select id, phone_e164 as phone, otp_hash as "otpHash",
              expires_at as "expiresAt", attempts,
              consumed_at as "consumedAt",
              provider_message_id as "providerMessageId"
       from public.otp_challenges
       where phone_e164 = $1
         and consumed_at is null
         and expires_at > $2
       order by created_at desc
       limit 1`,
      [phone, now]
    );

    return result.rows[0] ?? null;
  }

  async consume(id: string, now: Date): Promise<void> {
    await requireDb().query(
      `update public.otp_challenges
       set consumed_at = $2
       where id = $1 and consumed_at is null`,
      [id, now]
    );
  }

  async incrementAttempts(id: string): Promise<number> {
    const result = await requireDb().query(
      `update public.otp_challenges
       set attempts = attempts + 1
       where id = $1 and consumed_at is null
       returning attempts`,
      [id]
    );

    if (result.rowCount !== 1) throw new Error("OTP_INVALID_OR_EXPIRED");
    return Number(result.rows[0].attempts);
  }
}
