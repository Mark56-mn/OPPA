import { createHmac, randomBytes } from "node:crypto";

/**
 * Refresh tokens are random 256-bit values, stored only as a peppered HMAC
 * digest. The pepper means a database leak alone cannot be replayed against
 * the API, and a leaked pepper alone cannot be replayed against the database.
 */
export function generateRefreshToken(): string {
  return randomBytes(32).toString("base64url");
}

export function hashRefreshToken(token: string, pepper: string): string {
  if (!pepper) throw new Error("SESSION_INPUT_INVALID");
  return createHmac("sha256", pepper).update(token).digest("hex");
}
