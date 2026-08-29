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

      const result = await auth.requestOtp(phone);
      res.status(202).json(result);
    } catch (error) {
      next(error);
    }
  });

  router.post("/otp/verify", requireJsonBody, async (req, res, next) => {
    try {
      const phone = req.body?.phone;
      const code = req.body?.code;

      if (typeof phone !== "string" || typeof code !== "string") {
        res.status(400).json({ error: "PHONE_AND_CODE_REQUIRED", requestId: res.locals.requestId });
        return;
      }

      const result = await auth.verifyOtp(phone, code);
      res.status(200).json(result);
    } catch (error) {
      next(error);
    }
  });

  return router;
}
