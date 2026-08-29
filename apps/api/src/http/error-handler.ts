import type { ErrorRequestHandler } from "express";

export const errorHandler: ErrorRequestHandler = (error, _req, res, _next) => {
  const message = error instanceof Error ? error.message : "UNKNOWN_ERROR";

  if (message === "PHONE_INVALID") {
    res.status(400).json({ error: message, requestId: res.locals.requestId });
    return;
  }

  if (message.startsWith("OTP_ALREADY_ACTIVE:") || message === "OTP_RATE_LIMITED") {
    res.status(429).json({ error: message.split(":")[0], requestId: res.locals.requestId });
    return;
  }

  if (message === "OTP_INVALID_OR_EXPIRED" || message === "OTP_ATTEMPTS_EXCEEDED") {
    res.status(401).json({ error: "OTP_INVALID_OR_EXPIRED", requestId: res.locals.requestId });
    return;
  }

  console.error(error);
  if (res.headersSent) return;
  res.status(500).json({ error: "INTERNAL_SERVER_ERROR", requestId: res.locals.requestId });
};
