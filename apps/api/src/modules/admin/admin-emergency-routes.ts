import { Router } from "express";
import { db } from "../../db/pool.js";
import { requirePermission } from "./rbac.js";

const EMERGENCY_ACTIONS = new Set([
  "freeze_user", "unfreeze_user", "revoke_all_sessions", "suspend_business", "restore_business"
]);

function requireDb() {
  if (!db) throw new Error("DATABASE_URL is not configured");
  return db;
}

/**
 * Emergency controls: strong authorization (emergency.execute permission),
 * explicit reason capture (5-500 chars), explicit confirmation token and
 * append-only audit for every action. No destructive action happens without
 * all three. Admins can never target themselves with freeze/revoke.
 */
export function createAdminEmergencyRouter() {
  const r = Router();

  // Audit trail view (append-only log).
  r.get("/audit", requirePermission("audit.read"), async (req: any, res, next) => {
    try {
      const limit = Number(req.query.limit ?? 50);
      if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw Error("AUDIT_PAGINATION_INVALID");
      const before = typeof req.query.before === "string" && req.query.before.length <= 64 ? req.query.before : null;
      const q = await requireDb().query(
        `select id, actor_user_id as "actorUserId", event_type as "eventType",
                entity_type as "entityType", entity_id as "entityId", request_id as "requestId",
                metadata, created_at as "createdAt"
         from public.oppa_audit_events
         where ($2::timestamptz is null or created_at < $2::timestamptz)
         order by created_at desc limit $1`,
        [limit, before]
      );
      res.json({ events: q.rows });
    } catch (e) { next(e); }
  });

  // Security events for a user (security center / risk review support).
  r.get("/security-events", requirePermission("fraud.review"), async (req: any, res, next) => {
    try {
      const userId = typeof req.query.userId === "string" ? req.query.userId : "";
      if (!userId || userId.length > 128) throw Error("USER_ID_REQUIRED");
      const limit = Number(req.query.limit ?? 50);
      if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw Error("AUDIT_PAGINATION_INVALID");
      const q = await requireDb().query(
        `select id, user_id as "userId", device_id as "deviceId", session_id as "sessionId",
                event_type as "eventType", severity, metadata, created_at as "createdAt"
         from public.oppa_security_events
         where user_id=$1
         order by created_at desc limit $2`,
        [userId, limit]
      );
      res.json({ events: q.rows });
    } catch (e) { next(e); }
  });

  // Users list with status (Control Center user management).
  r.get("/users", requirePermission("users.read"), async (req: any, res, next) => {
    try {
      const limit = Number(req.query.limit ?? 50);
      if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw Error("AUDIT_PAGINATION_INVALID");
      const before = typeof req.query.before === "string" && req.query.before.length <= 64 ? req.query.before : null;
      const q = await requireDb().query(
        `select u.id, u.phone_e164 as "phoneMasked", u.status, u.created_at as "createdAt",
                (select count(*)::int from public.oppa_devices d where d.user_id=u.id and d.status='active') as "activeDevices",
                (select count(*)::int from public.oppa_sessions s where s.user_id=u.id and s.revoked_at is null and s.expires_at > now()) as "activeSessions"
         from public.oppa_users u
         where ($2::timestamptz is null or u.created_at < $2::timestamptz)
         order by u.created_at desc limit $1`,
        [limit, before]
      );
      // Mask phone numbers: admins get recognizable, not raw, identifiers.
      const users = q.rows.map((row: any) => ({
        ...row,
        phoneMasked: typeof row.phoneMasked === "string"
          ? row.phoneMasked.slice(0, 6) + "****" + row.phoneMasked.slice(-3)
          : row.phoneMasked
      }));
      res.json({ users });
    } catch (e) { next(e); }
  });

  // Body validation runs BEFORE the RBAC database check so malformed requests
  // fail fast without a DB round-trip, and RBAC still fails closed when the DB
  // is unavailable.
  const emergency = Router();
  emergency.post("/emergency", (req: any, res, next) => {
    const actionType = typeof req.body?.actionType === "string" ? req.body.actionType : "";
    const targetUserId = typeof req.body?.targetUserId === "string" ? req.body.targetUserId : "";
    const reason = typeof req.body?.reason === "string" ? req.body.reason : "";
    const confirm = typeof req.body?.confirm === "string" ? req.body.confirm : "";
    if (!EMERGENCY_ACTIONS.has(actionType)) return next(Error("EMERGENCY_ACTION_TYPE_INVALID"));
    if (!targetUserId || targetUserId.length > 128) return next(Error("USER_ID_REQUIRED"));
    if (!reason || reason.length < 5 || reason.length > 500) return next(Error("EMERGENCY_REASON_INVALID"));
    if (confirm !== "CONFIRM") return next(Error("EMERGENCY_CONFIRMATION_INVALID"));
    if (["freeze_user", "revoke_all_sessions"].includes(actionType) && targetUserId === req.auth?.userId) {
      // An operator must not lock themselves out mid-incident.
      return next(Error("EMERGENCY_REASON_INVALID"));
    }
    next();
  }, requirePermission("emergency.execute"), async (req: any, res, next) => {
    const client = await requireDb().connect();
    try {
      const actionType = String(req.body.actionType);
      const targetUserId = String(req.body.targetUserId);
      const reason = String(req.body.reason);

      await client.query("begin");
      const target = await client.query(
        `select id, status from public.oppa_users where id=$1 for update`,
        [targetUserId]
      );
      if (!target.rows[0]) throw Error("USER_NOT_FOUND");

      let effect = "";
      if (actionType === "freeze_user") {
        await client.query(
          `update public.oppa_users set status='locked', updated_at=now() where id=$1 and status='active'`,
          [targetUserId]
        );
        // Frozen users lose all live sessions immediately.
        await client.query(
          `update public.oppa_sessions set revoked_at=now(), last_seen_at=now() where user_id=$1 and revoked_at is null`,
          [targetUserId]
        );
        effect = "user_frozen";
      } else if (actionType === "unfreeze_user") {
        const r2 = await client.query(
          `update public.oppa_users set status='active', updated_at=now() where id=$1 and status='locked'`,
          [targetUserId]
        );
        effect = r2.rowCount === 1 ? "user_unfrozen" : "no_change";
      } else if (actionType === "revoke_all_sessions") {
        await client.query(
          `update public.oppa_sessions set revoked_at=now(), last_seen_at=now() where user_id=$1 and revoked_at is null`,
          [targetUserId]
        );
        effect = "sessions_revoked";
      } else if (actionType === "suspend_business" || actionType === "restore_business") {
        const businessId = typeof req.body?.businessId === "string" ? req.body.businessId : "";
        if (!businessId || businessId.length > 128) throw Error("BUSINESS_NOT_FOUND");
        const owned = await client.query(`select id from public.oppa_businesses where id=$1`, [businessId]);
        if (!owned.rows[0]) throw Error("BUSINESS_NOT_FOUND");
        const nextStatus = actionType === "suspend_business" ? "suspended" : "active";
        await client.query(
          `update public.oppa_businesses set status=$2, updated_at=now() where id=$1`,
          [businessId, nextStatus]
        );
        effect = actionType === "suspend_business" ? "business_suspended" : "business_restored";
      }

      await client.query(
        `insert into public.oppa_emergency_actions(action_type,target_user_id,reason,created_by)
         values($1,$2,$3,$4)`,
        [actionType, targetUserId, reason, req.auth.userId]
      );
      await client.query(
        `insert into public.oppa_audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)
         values($1,'admin.emergency_action','user',$2,$3::jsonb)`,
        [req.auth.userId, targetUserId, JSON.stringify({ actionType, reason, effect })]
      );
      await client.query("commit");
      res.status(201).json({ ok: true, effect });
    } catch (e) {
      try { await client.query("rollback"); } catch {}
      next(e);
    } finally {
      client.release();
    }
  });

  r.use(emergency);
  return r;
}
