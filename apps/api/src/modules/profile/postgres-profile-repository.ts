import { db } from "../../db/pool.js";
import type { Profile, ProfileRepository } from "./profile-repository.js";

function requireDb() { if (!db) throw new Error("DATABASE_URL is not configured"); return db; }

export class PostgresProfileRepository implements ProfileRepository {
  async get(userId: string): Promise<Profile> {
    const r = await requireDb().query(
      `select user_id as "userId", display_name as "displayName", avatar_url as "avatarUrl", about
       from public.oppa_profiles where user_id = $1`, [userId]
    );
    return r.rows[0] ?? { userId, displayName: null, avatarUrl: null, about: null };
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
}
