import { db } from "../../db/pool.js";
import type { IdentityRepository, UserIdentity } from "./identity-repository.js";

function requireDb() {
  if (!db) throw new Error("DATABASE_URL is not configured");
  return db;
}

export class PostgresIdentityRepository implements IdentityRepository {
  async findByPhone(phoneE164: string): Promise<UserIdentity | null> {
    const result = await requireDb().query(
      `select id, phone_e164 as "phoneE164", status,
              phone_verified_at as "phoneVerifiedAt"
       from public.oppa_users where phone_e164 = $1 limit 1`,
      [phoneE164]
    );
    return result.rows[0] ?? null;
  }

  async createVerified(phoneE164: string, verifiedAt: Date): Promise<UserIdentity> {
    const result = await requireDb().query(
      `insert into public.oppa_users (phone_e164, phone_verified_at)
       values ($1, $2)
       returning id, phone_e164 as "phoneE164", status,
                 phone_verified_at as "phoneVerifiedAt"`,
      [phoneE164, verifiedAt]
    );
    return result.rows[0];
  }

  async markPhoneVerified(userId: string, verifiedAt: Date): Promise<void> {
    await requireDb().query(
      `update public.oppa_users
       set phone_verified_at = $2, updated_at = now()
       where id = $1`,
      [userId, verifiedAt]
    );
  }
}
