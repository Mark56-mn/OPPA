import { strict as assert } from "node:assert";
import test from "node:test";
import { issueAccessToken, verifyAccessToken } from "./access-token.js";

test("issued access token verifies", () => {
  const now = Date.parse("2026-01-01T00:00:00Z");
  const issued = issueAccessToken("user-1", "session-1", "secret", now);
  const claims = verifyAccessToken(issued.token, "secret", now);
  assert.equal(claims.userId, "user-1");
  assert.equal(claims.sessionId, "session-1");
});

test("tampering is rejected", () => {
  const now = Date.parse("2026-01-01T00:00:00Z");
  const issued = issueAccessToken("user-1", "session-1", "secret", now);
  assert.throws(() => verifyAccessToken(issued.token + "x", "secret", now), /ACCESS_TOKEN_INVALID/);
});

test("expired token is rejected", () => {
  const now = Date.parse("2026-01-01T00:00:00Z");
  const issued = issueAccessToken("user-1", "session-1", "secret", now);
  assert.throws(
    () => verifyAccessToken(issued.token, "secret", now + 15 * 60 * 1000),
    /ACCESS_TOKEN_INVALID/
  );
});
