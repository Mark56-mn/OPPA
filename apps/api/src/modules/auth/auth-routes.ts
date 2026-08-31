import { Router } from "express";
import type { AuthService } from "./auth-service.js";
import { requireJsonBody } from "../../http/validate.js";

export function createAuthRouter(auth: AuthService) {
  const router = Router();

  router.post("/otp/request", requireJsonBody, async (req, res, next) => {
    try {
      const phone = req.body?.phone;
      if (typeof phone !== "string") {
        res.status(400).json({ error: "PHONE_REQUIRED", requestId: res.locals.requestId });
        return;
      }
      res.status(202).json(await auth.requestOtp(phone));
    } catch (error) {
      next(error);
    }
  });

  router.post("/otp/verify", requireJsonBody, async (req, res, next) => {
    try {
      const phone = req.body?.phone;
      const code = req.body?.code;
      const deviceId = req.body?.deviceId;
      if (typeof phone !== "string" || typeof code !== "string" || typeof deviceId !== "string") {
        res.status(400).json({
          error: "PHONE_CODE_AND_DEVICE_ID_REQUIRED",
          requestId: res.locals.requestId
        });
        return;
      }
      res.status(200).json(await auth.verifyOtp(phone, code, deviceId));
    } catch (error) {
      next(error);
    }
  });

  router.post("/refresh", requireJsonBody, async (req, res, next) => {
    try {
      const refreshToken = req.body?.refreshToken;
      if (typeof refreshToken !== "string") {
        res.status(400).json({ error: "REFRESH_TOKEN_REQUIRED", requestId: res.locals.requestId });
        return;
      }
      res.status(200).json(await auth.refresh(refreshToken));
    } catch (error) {
      next(error);
    }
  });

  return router;
}
