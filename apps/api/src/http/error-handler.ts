import type { ErrorRequestHandler } from "express";

const statuses: Record<string, number> = {
  FORBIDDEN: 403,
  USER_NOT_FOUND: 404,
  MESSAGE_BODY_REQUIRED: 400,
  MESSAGE_TOO_LONG: 413,
  PHONE_INVALID: 400,
  OTP_INVALID_OR_EXPIRED: 401,
  OTP_ATTEMPTS_EXCEEDED: 429,
  OTP_RATE_LIMITED: 429,
  OTP_ALREADY_ACTIVE: 429,
  ACCOUNT_UNAVAILABLE: 403,
  DEVICE_ID_INVALID: 400,
  DEVICE_KEY_INVALID: 400,
  PROFILE_FIELD_INVALID: 400,
  PROFILE_FIELD_TOO_LONG: 400,
  CONVERSATION_SELF_INVALID: 400,
  CONTACT_SELF_INVALID: 400,
  REFRESH_TOKEN_INVALID: 401,
  WALLET_AMOUNT_INVALID: 400,
  WALLET_BALANCE_INVALID: 500,
  WALLET_REFERENCE_INVALID: 400,
  WALLET_REFERENCE_REUSED: 409,
  WALLET_INSUFFICIENT_FUNDS: 409,
  WALLET_TRANSFER_SELF: 400
};

export const errorHandler: ErrorRequestHandler = (error, _req, res, _next) => {
  console.error("request_error", {
    name: error?.name,
    code: typeof error?.message === "string" ? error.message : "INTERNAL_SERVER_ERROR"
  });
  if (res.headersSent) return;

  const code = typeof error?.message === "string" && statuses[error.message]
    ? error.message
    : "INTERNAL_SERVER_ERROR";

  res.status(statuses[code] ?? 500).json({
    error: code,
    requestId: res.locals.requestId
  });
};
