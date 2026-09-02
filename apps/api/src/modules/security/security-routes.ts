import { Router } from "express";
import type { SecurityService } from "./security-service.js";
import { assertSensitiveOperation } from "./sensitive-authorization.js";

export function createSecurityRouter(security: SecurityService) {
  const router = Router();

  router.post("/step-up/challenge", async (req, res, next) => {
    try {
      const purpose = assertSensitiveOperation(typeof req.body?.purpose === "string" ? req.body.purpose : "");
      const deviceId = typeof req.body?.deviceId === "string" ? req.body.deviceId : "";
      if (!deviceId || deviceId.length > 128) throw new Error("DEVICE_ID_INVALID");
      res.status(201).json(await security.createStepUp(req.auth!.userId, purpose, deviceId));
    } catch (e) { next(e); }
  });

  return router;
}
