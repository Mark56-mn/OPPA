import assert from "node:assert/strict";
import test from "node:test";
import type { AddressInfo } from "node:net";
import express from "express";
import { errorHandler } from "../../http/error-handler.js";
import { createProfileRouter } from "./profile-routes.js";
import { validateOppaId } from "./postgres-profile-repository.js";
import type { ProfileRepository, Profile } from "./profile-repository.js";

function profile(overrides: Partial<Profile> = {}): Profile {
  return { userId: "u1", displayName: null, avatarUrl: null, about: null, oppaId: null, ...overrides };
}

function repo(overrides: Partial<ProfileRepository> = {}): ProfileRepository {
  const claims = new Map<string, string>([["taken_id", "someone-else"]]);
  const changes: string[] = [];
  return {
    async get(userId) { return profile({ userId }); },
    async upsert(userId) { return profile({ userId }); },
    async isOppaIdAvailable(id, exceptUserId) { return !(claims.has(id) && claims.get(id) !== exceptUserId); },
    async setOppaId(userId, id) {
      changes.push(`${userId}:${id}`);
      const normalized = String(id).trim().toLowerCase();
      if (claims.has(normalized) && claims.get(normalized) !== userId) throw new Error("OPPA_ID_TAKEN");
      claims.set(normalized, userId);
      return profile({ userId, oppaId: normalized });
    },
    async findByOppaId(id) {
      const owner = claims.get(id);
      return owner ? { userId: owner, displayName: "X", oppaId: id } : null;
    },
    ...overrides,
  } as ProfileRepository;
}

async function listen(app: express.Express): Promise<{ url: string; close: () => Promise<void> }> {
  const server = await new Promise<import("node:http").Server>((resolve) => {
    const s = app.listen(0, "127.0.0.1", () => resolve(s));
  });
  const { port } = server.address() as AddressInfo;
  return { url: `http://127.0.0.1:${port}`, close: () => new Promise((resolve) => server.close(() => resolve())) };
}

function appFor(repository: ProfileRepository, userId = "u1") {
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => { req.auth = { userId, sessionId: "s1" }; next(); });
  app.use("/profile", createProfileRouter(repository));
  app.use(errorHandler);
  return app;
}

test("oppa id validation rejects bad shapes and reserved names", () => {
  assert.equal(validateOppaId("ada01"), "ada01");
  assert.throws(() => validateOppaId("ab"), { message: "OPPA_ID_INVALID" });
  assert.throws(() => validateOppaId("1abc"), { message: "OPPA_ID_INVALID" });
  assert.throws(() => validateOppaId("UPPER-case!"), { message: "OPPA_ID_INVALID" });
  assert.throws(() => validateOppaId("admin"), { message: "OPPA_ID_RESERVED" });
  assert.throws(() => validateOppaId("whatsapp"), { message: "OPPA_ID_RESERVED" });
  assert.throws(() => validateOppaId(42 as any), { message: "OPPA_ID_INVALID" });
  // Normalization: trims and lowercases.
  assert.equal(validateOppaId("  Ada_01 "), "ada_01");
});

test("availability reports taken ids without revealing the holder", async () => {
  const app = appFor(repo());
  const srv = await listen(app);
  try {
    const free = await fetch(`${srv.url}/profile/oppa-id/available/ada_01`);
    assert.equal((await free.json() as any).available, true);
    const taken = await fetch(`${srv.url}/profile/oppa-id/available/taken_id`);
    const body = await taken.json() as any;
    assert.equal(body.available, false);
    assert.equal(body.reason, "OPPA_ID_TAKEN");
    assert.equal(body.userId, undefined);
    const invalid = await fetch(`${srv.url}/profile/oppa-id/available/x`);
    assert.equal((await invalid.json() as any).available, false);
  } finally { await srv.close(); }
});

test("claiming an id is validated, rate-limited and auditable via response", async () => {
  const repository = repo();
  const app = appFor(repository);
  const srv = await listen(app);
  try {
    const ok = await fetch(`${srv.url}/profile/oppa-id`, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ oppaId: "Ada_01" }),
    });
    assert.equal(ok.status, 200);
    assert.equal((await ok.json() as any).oppaId, "ada_01");
    // Taken id from another user → 409.
    const taken = await fetch(`${srv.url}/profile/oppa-id`, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ oppaId: "taken_id" }),
    });
    assert.equal(taken.status, 409);
    // Invalid shape → 400.
    const invalid = await fetch(`${srv.url}/profile/oppa-id`, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ oppaId: "no" }),
    });
    assert.equal(invalid.status, 400);
    // Rate limit: 3 changes/hour (the first success above counts).
    let last = 200;
    for (let i = 0; i < 3; i++) {
      const r = await fetch(`${srv.url}/profile/oppa-id`, {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ oppaId: `handle_${i}x` }),
      });
      last = r.status;
    }
    assert.equal(last, 429);
  } finally { await srv.close(); }
});

test("lookup by oppa id returns minimal public identity or 404", async () => {
  const repository = repo();
  const app = appFor(repository);
  const srv = await listen(app);
  try {
    await fetch(`${srv.url}/profile/oppa-id`, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ oppaId: "find_me" }),
    });
    const found = await fetch(`${srv.url}/profile/oppa-id/lookup/find_me`);
    assert.equal(found.status, 200);
    const body = await found.json() as any;
    assert.equal(body.oppaId, "find_me");
    assert.equal(body.userId, "u1");
    assert.equal(body.phone, undefined);
    const missing = await fetch(`${srv.url}/profile/oppa-id/lookup/nobody_here`);
    assert.equal(missing.status, 404);
    const invalid = await fetch(`${srv.url}/profile/oppa-id/lookup/BAD!`);
    assert.equal(invalid.status, 404);
  } finally { await srv.close(); }
});
