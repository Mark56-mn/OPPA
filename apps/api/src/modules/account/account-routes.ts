import { Router } from "express";
import type { SessionService } from "../session/session-service.js";
import type { DeviceService } from "../device/device-service.js";
import { db } from "../../db/pool.js";

function requireDb() {
  if (!db) throw new Error("DATABASE_URL is not configured");
  return db;
}

function pagination(query: { limit?: unknown; before?: unknown; offset?: unknown }) {
  const limit = Number(query.limit ?? 50);
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) {
    throw new Error("ACCOUNT_PAGINATION_INVALID");
  }
  const before = typeof query.before === "string" && query.before.length <= 64 ? query.before : undefined;
  const offset = Number(query.offset ?? 0);
  if (!Number.isSafeInteger(offset) || offset < 0) {
    throw new Error("ACCOUNT_PAGINATION_INVALID");
  }
  return { limit, before: before ?? null, offset };
}

const DEVICE_PLATFORMS = new Set(["android", "ios", "web", "unknown"]);
const SESSION_STATES = new Set(["active", "expired", "revoked"]);

/**
 * Account surface: everything a user needs to manage their own security
 * posture — logout, device and session visibility, and revocation. Revoking a
 * device cascades to its sessions via the active-device checks in every
 * session lookup, so a revoked device cannot keep working.
 */
export function createAccountRouter(
  sessions: SessionService,
  devices: DeviceService,
  securityEvents: { record(input: { userId: string; eventType: string; severity: "info" | "warning" | "critical"; metadata?: Record<string, unknown> }): Promise<void> }
) {
  const router = Router();

  router.post("/logout", async (req, res, next) => {
    try {
      await sessions.revoke(req.auth!.sessionId);
      res.status(204).send();
    } catch (e) { next(e); }
  });

  router.get("/devices", async (req, res, next) => {
    try {
      const q = requireDb().query(
        `select d.id, d.platform, d.status, d.registered_at as "registeredAt",
                d.last_seen_at as "lastSeenAt",
                (select count(*)::int from public.oppa_sessions s
                 where s.device_id = d.id and s.revoked_at is null and s.expires_at > now()) as "activeSessions"
         from public.oppa_devices d
         where d.user_id = $1
         order by d.status asc, d.registered_at desc
         limit 200`,
        [req.auth!.userId]
      );
      res.json({ devices: (await q).rows });
    } catch (e) { next(e); }
  });

  router.get("/sessions", async (req, res, next) => {
    try {
      const { limit, before, offset } = pagination(req.query);
      const q = requireDb().query(
        `select s.id, s.device_id as "deviceId", d.platform,
                case
                  when s.revoked_at is not null then 'revoked'
                  when s.expires_at <= now() then 'expired'
                  else 'active'
                end as state,
                s.created_at as "createdAt",
                s.last_seen_at as "lastSeenAt",
                (s.id = $1) as "isCurrent",
                (s.id = $1 and s.revoked_at is null and s.expires_at > now()) as "isCurrentActive"
         from public.oppa_sessions s
         left join public.oppa_devices d on d.id = s.device_id
         where s.user_id = $2
           and ($3::timestamptz is null or s.created_at < $3)
         order by s.created_at desc
         limit $4 offset $5`,
        [req.auth!.sessionId, req.auth!.userId, before, limit, offset]
      );
      const rows = (await q).rows;
      res.json({ sessions: rows.filter((r: any) => SESSION_STATES.has(r.state)) });
    } catch (e) { next(e); }
  });

  router.post("/sessions/:sessionId/revoke", async (req, res, next) => {
    try {
      const target = String(req.params.sessionId);
      if (!target || target.length > 128) throw new Error("SESSION_ID_INVALID");
      const owned = await requireDb().query(
        `update public.oppa_sessions set revoked_at = now(), last_seen_at = now()
         where id = $1 and user_id = $2 and revoked_at is null`,
        [target, req.auth!.userId]
      );
      if (owned.rowCount !== 1) throw new Error("SESSION_NOT_FOUND");
      if (target !== req.auth!.sessionId) {
        await securityEvents.record({
          userId: req.auth!.userId,
          eventType: "security.session_revoked",
          severity: "info",
          metadata: { sessionId: target, revokedBySession: req.auth!.sessionId }
        });
      }
      res.status(204).send();
    } catch (e) { next(e); }
  });

  router.post("/devices/:deviceId/revoke", async (req, res, next) => {
    try {
      const target = String(req.params.deviceId);
      if (!target || target.length > 128) throw new Error("DEVICE_ID_INVALID");
      await devices.revokeDevice(req.auth!.userId, target);
      await securityEvents.record({
        userId: req.auth!.userId,
        eventType: "security.device_revoked",
        severity: "warning",
        metadata: { deviceId: target }
      });
      res.status(204).send();
    } catch (e) { next(e); }
  });

  return router;
}
