import type { RequestHandler } from "express";
import { verifyAccessToken } from "../modules/session/access-token.js";
import type { SessionRepository } from "../modules/session/session-repository.js";

declare global {
  namespace Express {
    interface Request {
      auth?: { userId: string; sessionId: string };
    }
  }
}

export function createRequireAuth(accessSecret: string, sessions: SessionRepository): RequestHandler {
  return async (req, res, next) => {
    const authorization = req.header("authorization");
    if (!authorization?.startsWith("Bearer ")) {
      res.status(401).json({ error: "UNAUTHORIZED", requestId: res.locals.requestId });
      return;
    }

    try {
      const claims = verifyAccessToken(authorization.slice(7), accessSecret);
      if (!(await sessions.isActive(claims.sessionId, claims.userId, new Date()))) {
        res.status(401).json({ error: "UNAUTHORIZED", requestId: res.locals.requestId });
        return;
      }
      req.auth = { userId: claims.userId, sessionId: claims.sessionId };
      next();
    } catch {
      res.status(401).json({ error: "UNAUTHORIZED", requestId: res.locals.requestId });
    }
  };
}
