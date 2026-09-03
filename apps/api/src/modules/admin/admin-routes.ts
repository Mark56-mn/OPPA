import { Router } from "express";
import { db } from "../../db/pool.js";
import { requirePermission } from "./rbac.js";
import type { PostgresRiskRepository } from "../risk/postgres-risk-repository.js";

const DECISIONS = new Set(["allow", "review", "block"]);
const SCOPES = new Set(["user", "transfer", "payment", "otp", "login"]);

export function createAdminRouter(risk?: PostgresRiskRepository) {
  const r = Router();
  r.get("/me/permissions", requirePermission("users.read"), async (req: any, res, next) => {
    try {
      if (!db) throw Error("DATABASE_URL is not configured");
      const q = await db.query(`select distinct p.code from public.oppa_staff s join public.oppa_staff_roles sr on sr.staff_id=s.id join public.oppa_role_permissions rp on rp.role_id=sr.role_id join public.oppa_permissions p on p.id=rp.permission_id where s.user_id=$1 and s.status='active' order by p.code`, [req.auth.userId]);
      res.json({ permissions: q.rows.map((x) => x.code) });
    } catch (e) { next(e); }
  });

  r.get("/risk/decisions", requirePermission("fraud.review"), async (req: any, res, next) => {
    try {
      if (!risk) throw Error("RISK_SERVICE_UNAVAILABLE");
      const userId = typeof req.query.userId === "string" ? req.query.userId : "";
      const limit = Number(req.query.limit ?? 50);
      if (!userId) throw Error("USER_ID_REQUIRED");
      if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw Error("RISK_PAGINATION_INVALID");
      res.json({ decisions: await risk.listDecisions(userId, limit) });
    } catch (e) { next(e); }
  });

  r.get("/risk/events", requirePermission("fraud.review"), async (req: any, res, next) => {
    try {
      if (!risk) throw Error("RISK_SERVICE_UNAVAILABLE");
      const userId = typeof req.query.userId === "string" ? req.query.userId : "";
      const limit = Number(req.query.limit ?? 50);
      if (!userId) throw Error("USER_ID_REQUIRED");
      if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw Error("RISK_PAGINATION_INVALID");
      res.json({ events: await risk.listRecentEvents(userId, limit) });
    } catch (e) { next(e); }
  });

  r.post("/risk/decisions", requirePermission("fraud.review"), async (req: any, res, next) => {
    try {
      if (!risk) throw Error("RISK_SERVICE_UNAVAILABLE");
      const userId = typeof req.body?.userId === "string" ? req.body.userId : "";
      const scope = typeof req.body?.scope === "string" ? req.body.scope : "";
      const decision = typeof req.body?.decision === "string" ? req.body.decision : "";
      const reason = typeof req.body?.reason === "string" ? req.body.reason : "";
      if (!userId || userId.length > 128) throw Error("USER_ID_REQUIRED");
      if (!SCOPES.has(scope)) throw Error("RISK_SCOPE_INVALID");
      if (!DECISIONS.has(decision)) throw Error("RISK_DECISION_INVALID");
      if (!reason || reason.length > 500) throw Error("RISK_REASON_INVALID");
      let expiresAt: Date | undefined;
      if (req.body?.expiresAt != null) {
        if (typeof req.body.expiresAt !== "string") throw Error("RISK_EXPIRY_INVALID");
        expiresAt = new Date(req.body.expiresAt);
        if (Number.isNaN(expiresAt.getTime())) throw Error("RISK_EXPIRY_INVALID");
      }
      await risk.createDecision({ userId, scope, decision: decision as any, reason, expiresAt, createdBy: req.auth.userId });
      res.status(201).json({ ok: true });
    } catch (e) { next(e); }
  });
  return r;
}