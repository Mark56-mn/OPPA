import { db } from "../../db/pool.js";
import type { Profile, ProfileRepository } from "./profile-repository.js";

function requireDb() { if (!db) throw new Error("DATABASE_URL is not configured"); return db; }

/**
 * OPPA ID validation. Server-authoritative: the client can only propose a
 * handle; this function decides. Rules are conservative to prevent
 * impersonation and look-alike handles:
 *   3–32 chars, [a-z0-9_], must start with a letter, at least one letter.
 */
export const OPPA_ID_PATTERN = /^[a-z][a-z0-9_]{2,31}$/;

/** Product/system terms that can never be used as an OPPA ID. */
const RESERVED_OPPA_IDS = new Set([
  "oppa", "admin", "administrator", "root", "system", "support", "help",
  "security", "wallet", "payments", "paystack", "flutterwave", "business",
  "official", "team", "staff", "moderator", "mod", "abuse", "fraud",
  "null", "undefined", "whatsapp", "wa", "meta",
]);

export function validateOppaId(raw: unknown): string {
  if (typeof raw !== "string") throw new Error("OPPA_ID_INVALID");
  const id = raw.trim().toLowerCase();
  if (!OPPA_ID_PATTERN.test(id)) throw new Error("OPPA_ID_INVALID");
  if (RESERVED_OPPA_IDS.has(id)) throw new Error("OPPA_ID_RESERVED");
  return id;
}

export class PostgresProfileRepository implements ProfileRepository {
  async get(userId: string): Promise<Profile> {
    const r = await requireDb().query(
      `select user_id as "userId", display_name as "displayName", avatar_url as "avatarUrl", about,
              oppa_id as "oppaId"
       from public.oppa_profiles where user_id = $1`, [userId]
    );
    return r.rows[0] ?? { userId, displayName: null, avatarUrl: null, about: null, oppaId: null };
  }

  async upsert(userId: string, input: { displayName?: string | null; avatarUrl?: string | null; about?: string | null }): Promise<Profile> {
    const r = await requireDb().query(
      `insert into public.oppa_profiles (user_id, display_name, avatar_url, about)
       values ($1,$2,$3,$4)
       on conflict (user_id) do update set
         display_name = coalesce(excluded.display_name, public.oppa_profiles.display_name),
         avatar_url = coalesce(excluded.avatar_url, public.oppa_profiles.avatar_url),
         about = coalesce(excluded.about, public.oppa_profiles.about),
         updated_at = now()
       returning user_id as "userId", display_name as "displayName", avatar_url as "avatarUrl", about`,
      [userId, input.displayName ?? null, input.avatarUrl ?? null, input.about ?? null]
    );
    return r.rows[0];
  }

  /** True when the handle is valid AND not taken by anyone else. */
  async isOppaIdAvailable(id: string, exceptUserId: string): Promise<boolean> {
    const r = await requireDb().query(
      `select 1 from public.oppa_profiles where oppa_id = $1 and user_id <> $2 limit 1`,
      [id, exceptUserId]
    );
    return r.rows.length === 0;
  }

  /** Set/replace the caller's OPPA ID. Unique-index-safe: a lost race
   *  surfaces as OPPA_ID_TAKEN. Audit event written in the same transaction. */
  async setOppaId(userId: string, rawId: string): Promise<Profile> {
    const id = validateOppaId(rawId);
    const client = await requireDb().connect();
    try {
      await client.query("begin");
      const previous = await client.query(
        `select oppa_id from public.oppa_profiles where user_id = $1 for update`,
        [userId]
      );
      const had = previous.rows[0]?.oppa_id ?? null;
      const r = await client.query(
        `insert into public.oppa_profiles (user_id, oppa_id)
         values ($1, $2)
         on conflict (user_id) do update set oppa_id = $2, updated_at = now()
         returning user_id as "userId", display_name as "displayName",
                   avatar_url as "avatarUrl", about, oppa_id as "oppaId"`,
        [userId, id]
      );
      await client.query(
        `insert into public.oppa_audit_events(actor_user_id, event_type, entity_type, entity_id, metadata)
         values ($1, 'profile.oppa_id_set', 'user', $1, $2::jsonb)`,
        [userId, JSON.stringify({ oppaId: id, previous: had })]
      );
      await client.query("commit");
      return r.rows[0];
    } catch (e: any) {
      try { await client.query("rollback"); } catch {}
      // Unique violation on oppa_id → friendly, stable error.
      if (e?.code === "23505") throw new Error("OPPA_ID_TAKEN");
      throw e;
    } finally { client.release(); }
  }

  /** Lookup by OPPA ID for Connect/discovery. Returns the minimal public
   *  identity only — never phone numbers or session data. */
  async findByOppaId(id: string): Promise<{ userId: string; displayName: string | null; oppaId: string } | null> {
    const r = await requireDb().query(
      `select p.user_id as "userId", p.display_name as "displayName", p.oppa_id as "oppaId",
              u.status
       from public.oppa_profiles p
       join public.oppa_users u on u.id = p.user_id
       where p.oppa_id = $1 and u.status = 'active'
       limit 1`,
      [id]
    );
    const row = r.rows[0];
    if (!row) return null;
    return { userId: row.userId, displayName: row.displayName ?? null, oppaId: row.oppaId };
  }
}
