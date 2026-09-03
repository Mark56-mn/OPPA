import { createHmac, randomBytes, timingSafeEqual } from "node:crypto";

const ACCESS_TTL_SECONDS = 15 * 60;
const PREFIX = "oppa_at_";

function base64url(value: Buffer): string {
  return value.toString("base64url");
}

export function issueAccessToken(userId: string, sessionId: string, secret: string, now = Date.now()) {
  const expiresAt = Math.floor(now / 1000) + ACCESS_TTL_SECONDS;
  const nonce = base64url(randomBytes(18));
  const payload = base64url(Buffer.from(JSON.stringify({ sub: userId, sid: sessionId, exp: expiresAt, n: nonce })));
  const signature = base64url(createHmac("sha256", secret).update(payload).digest());
  return { token: PREFIX + payload + "." + signature, expiresAt: new Date(expiresAt * 1000) };
}

export function verifyAccessToken(token: string, secret: string, now = Date.now()): { userId: string; sessionId: string; expiresAt: Date } {
  if (!token || token.length > 4096 || !token.startsWith(PREFIX)) throw new Error("ACCESS_TOKEN_INVALID");
  const value = token.slice(PREFIX.length);
  const [payload, signature] = value.split(".");
  if (!payload || !signature) throw new Error("ACCESS_TOKEN_INVALID");

  const expected = createHmac("sha256", secret).update(payload).digest();
  const supplied = Buffer.from(signature, "base64url");
  if (supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) {
    throw new Error("ACCESS_TOKEN_INVALID");
  }

  let claims: { sub?: unknown; sid?: unknown; exp?: unknown };
  try {
    claims = JSON.parse(Buffer.from(payload, "base64url").toString("utf8"));
  } catch {
    throw new Error("ACCESS_TOKEN_INVALID");
  }

  if (typeof claims.sub !== "string" || claims.sub.length === 0 || claims.sub.length > 128 || typeof claims.sid !== "string" || claims.sid.length === 0 || claims.sid.length > 128 ||
      typeof claims.exp !== "number" || !Number.isInteger(claims.exp) ||
      claims.exp <= Math.floor(now / 1000)) {
    throw new Error("ACCESS_TOKEN_INVALID");
  }

  return {
    userId: claims.sub,
    sessionId: claims.sid,
    expiresAt: new Date(claims.exp * 1000)
  };
}
