import type { RequestHandler } from "express";

declare global {
  namespace Express {
    interface Request {
      auth?: { userId: string; sessionId: string };
    }
  }
}

export const requireAuth: RequestHandler = (req, res, next) => {
  const authorization = req.header("authorization");
  if (!authorization?.startsWith("Bearer ")) {
    res.status(401).json({ error: "UNAUTHORIZED", requestId: res.locals.requestId });
    return;
  }

  // Token verification is intentionally not accepted here until a persistent
  // access-token verifier is wired to the session store.
  res.status(501).json({ error: "AUTH_VERIFIER_NOT_READY", requestId: res.locals.requestId });
};
