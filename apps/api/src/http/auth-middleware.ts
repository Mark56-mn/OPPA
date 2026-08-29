import type { RequestHandler } from "express";
import { verifyAccessToken } from "../modules/session/access-token.js";

declare global {
  namespace Express {
    interface Request {
      auth?: { userId: string; sessionId: string };
    }
  }
}

export function createRequireAuth(accessSecret: string): RequestHandler {
  return (req, res, next) => {
    const authorization = req.header("authorization");
    if (!authorization?.startsWith("Bearer ")) {
      res.status(401).json({ error: "UNAUTHORIZED", requestId: res.locals.requestId });
      return;
    }

    try {
      const claims = verifyAccessToken(authorization.slice(7), accessSecret);
      req.auth = { userId: claims.userId, sessionId: claims.sessionId };
      next();
    } catch {
      res.status(401).json({ error: "UNAUTHORIZED", requestId: res.locals.requestId });
    }
  };
}
