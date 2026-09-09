import { Router } from "express";
import type { ProfileRepository } from "./profile-repository.js";
import { requireJsonBody } from "../../http/validate.js";
import { validateOppaId } from "./postgres-profile-repository.js";

export function createProfileRouter(profiles: ProfileRepository) {
  const router = Router();

  // In-process rate limit for OPPA ID changes: 3 per hour per user, scoped
  // to this router instance. Bounds handle-squatting churn; the unique-index
  // collision path is separate.
  const oppaIdChangeTimes = new Map<string, number[]>();
  const oppaIdChangeAllowed = (userId: string): boolean => {
    const now = Date.now();
    const windowStart = now - 60 * 60 * 1000;
    const hits = (oppaIdChangeTimes.get(userId) ?? []).filter((t) => t > windowStart);
    if (hits.length >= 3) return false;
    hits.push(now);
    oppaIdChangeTimes.set(userId, hits);
    return true;
  };
  router.get("/", async (req,res,next) => {
    try { res.json(await profiles.get(req.auth!.userId)); } catch(e) { next(e); }
  });
  router.patch("/", requireJsonBody, async (req,res,next) => {
    try {
      const body=req.body ?? {};
      for (const key of ["displayName","avatarUrl","about"]) {
        if (body[key] !== undefined && body[key] !== null && typeof body[key] !== "string") {
          res.status(400).json({error:"PROFILE_FIELD_INVALID",requestId:res.locals.requestId}); return;
        }
      }
      if (typeof body.displayName === "string" && body.displayName.length > 80 ||
          typeof body.about === "string" && body.about.length > 280 ||
          typeof body.avatarUrl === "string" && body.avatarUrl.length > 2048) {
        res.status(400).json({error:"PROFILE_FIELD_TOO_LONG",requestId:res.locals.requestId}); return;
      }
      res.json(await profiles.upsert(req.auth!.userId, body));
    } catch(e) { next(e); }
  });

  // OPPA ID availability: shape-checked locally (no DB hit for garbage),
  // uniqueness answered by the server. Never reveals which specific user
  // holds an id — only taken/available.
  router.get("/oppa-id/available/:id", async (req,res,next) => {
    try {
      let id: string;
      try { id = validateOppaId(req.params.id); } catch { 
        res.status(200).json({ available: false, reason: "OPPA_ID_INVALID" }); return;
      }
      if (!profiles.isOppaIdAvailable) throw new Error("OPPA_ID_INVALID");
      const ok = await profiles.isOppaIdAvailable(id, req.auth!.userId);
      res.status(200).json({ available: ok, reason: ok ? null : "OPPA_ID_TAKEN" });
    } catch(e) { next(e); }
  });

  // Claim or change the caller's OPPA ID. Server validates shape, reserved
  // names, uniqueness and change rate. Audit event written server-side.
  router.post("/oppa-id", requireJsonBody, async (req,res,next) => {
    try {
      if (!profiles.setOppaId) throw new Error("OPPA_ID_INVALID");
      const id = validateOppaId(req.body?.oppaId); // shape/reserved first
      if (!oppaIdChangeAllowed(req.auth!.userId)) {
        throw new Error("OPPA_ID_CHANGE_RATE_LIMITED");
      }
      res.json(await profiles.setOppaId(req.auth!.userId, id));
    } catch(e) { next(e); }
  });

  // Public-by-handle lookup for Connect (minimal identity only, active
  // accounts only). Route order matters: registered before any /:id routes.
  router.get("/oppa-id/lookup/:id", async (req,res,next) => {
    try {
      let id: string;
      try { id = validateOppaId(req.params.id); } catch {
        res.status(404).json({ error: "OPPA_ID_NOT_FOUND", requestId: res.locals.requestId }); return;
      }
      if (!profiles.findByOppaId) throw new Error("OPPA_ID_INVALID");
      const found = await profiles.findByOppaId(id);
      if (!found) {
        res.status(404).json({ error: "OPPA_ID_NOT_FOUND", requestId: res.locals.requestId });
        return;
      }
      res.json(found);
    } catch(e) { next(e); }
  });
  return router;
}
