import { Router } from "express";
import type { ProfileRepository } from "./profile-repository.js";
import { requireJsonBody } from "../../http/validate.js";

export function createProfileRouter(profiles: ProfileRepository) {
  const router = Router();
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
  return router;
}
