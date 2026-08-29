import type { RequestHandler } from "express";

export const requireJsonBody: RequestHandler = (req, res, next) => {
  if (!req.is("application/json")) {
    res.status(415).json({ error: "UNSUPPORTED_MEDIA_TYPE", requestId: res.locals.requestId });
    return;
  }
  next();
};
