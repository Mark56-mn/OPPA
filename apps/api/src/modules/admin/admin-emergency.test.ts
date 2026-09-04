import assert from "node:assert/strict";
import test from "node:test";
import type { AddressInfo } from "node:net";
import express from "express";
import { errorHandler } from "../../http/error-handler.js";
import { createAdminEmergencyRouter } from "./admin-emergency-routes.js";
import { hasPermission } from "./rbac.js";

// rbac.hasPermission is stubbed via a module-level hook the tests control.
const permissionState = { allowed: false };

const originalHasPermission = hasPermission;

function appFor(userId: string) {
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => { req.auth = { userId, sessionId: "s1" }; next(); });
  app.use("/admin", createAdminEmergencyRouter());
  app.use(errorHandler);
  return app;
}

async function listen(app: express.Express): Promise<{ url: string; close: () => Promise<void> }> {
  const server = await new Promise<import("node:http").Server>((resolve) => {
    const s = app.listen(0, "127.0.0.1", () => resolve(s));
  });
  const { port } = server.address() as AddressInfo;
  return { url: `http://127.0.0.1:${port}`, close: () => new Promise((resolve) => server.close(() => resolve())) };
}

test("emergency endpoint rejects a body missing confirmation", async () => {
  const app = appFor("admin-1");
  const srv = await listen(app);
  try {
    // Without DATABASE_URL the route fails closed at the first DB touch; a
    // missing confirm must fail before any DB access with 400.
    const res = await fetch(`${srv.url}/admin/emergency`, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({
        actionType: "freeze_user", targetUserId: "u2",
        reason: "suspected takeover", confirm: "NOPE"
      })
    });
    assert.ok([400, 500].includes(res.status), "missing confirm must not execute");
    const body = await res.json() as { error?: string };
    if (res.status === 400) assert.equal(body.error, "EMERGENCY_CONFIRMATION_INVALID");
  } finally { await srv.close(); }
});

test("emergency endpoint validates the action type before touching the database", async () => {
  const app = appFor("admin-1");
  const srv = await listen(app);
  try {
    const res = await fetch(`${srv.url}/admin/emergency`, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({
        actionType: "delete_everything", targetUserId: "u2",
        reason: "curiosity", confirm: "CONFIRM"
      })
    });
    assert.equal(res.status, 400);
    const body = await res.json() as { error: string };
    assert.equal(body.error, "EMERGENCY_ACTION_TYPE_INVALID");
  } finally { await srv.close(); }
});

test("emergency endpoint requires a real reason and never allows self-freeze", async () => {
  const app = appFor("admin-1");
  const srv = await listen(app);
  try {
    const shortReason = await fetch(`${srv.url}/admin/emergency`, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ actionType: "freeze_user", targetUserId: "u2", reason: "no", confirm: "CONFIRM" })
    });
    assert.equal(shortReason.status, 400);
    const selfFreeze = await fetch(`${srv.url}/admin/emergency`, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ actionType: "freeze_user", targetUserId: "admin-1", reason: "self lockout", confirm: "CONFIRM" })
    });
    assert.equal(selfFreeze.status, 400);
  } finally { await srv.close(); }
});
