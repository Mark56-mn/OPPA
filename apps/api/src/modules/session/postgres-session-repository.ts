import { randomUUID } from "node:crypto";
import { db } from "../../db/pool.js";
import type { SessionRecord, SessionRepository } from "./session-repository.js";

function requireDb() {
  if (!db) throw new Error("DATABASE_URL is not configured");
  return db;
}

export class PostgresSessionRepository implements SessionRepository {
  async create(input: {
    userId: string;
    deviceId: string;
    refreshTokenHash: string;
    expiresAt: Date;
  }): Promise<SessionRecord> {
    const id = randomUUID();
    const result = await requireDb().query(
      `insert into public.oppa_sessions
       (id, user_id, device_id, refresh_token_hash, expires_at)
       values ($1, $2, $3, $4, $5)
       returning id, user_id as "userId", device_id as "deviceId",
                 expires_at as "expiresAt"`,
      [id, input.userId, input.deviceId, input.refreshTokenHash, input.expiresAt]
    );
    return result.rows[0];
  }

  async revoke(sessionId: string, revokedAt: Date): Promise<void> {
    await requireDb().query(
      `update public.oppa_sessions
       set revoked_at = $2, last_seen_at = $2
       where id = $1 and revoked_at is null`,
      [sessionId, revokedAt]
    );
  }
}
