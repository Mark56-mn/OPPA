import assert from "node:assert/strict";
import test from "node:test";
import { randomUUID, generateKeyPairSync, createSign } from "node:crypto";
import type { AddressInfo } from "node:net";
import express from "express";
import { requestId } from "./http/request-id.js";
import { errorHandler } from "./http/error-handler.js";
import { createRequireAuth } from "./http/auth-middleware.js";
import { SessionService } from "./modules/session/session-service.js";
import { SecurityService } from "./modules/security/security-service.js";
import { DeviceProofService } from "./modules/security/device-proof-service.js";
import { DefaultSensitiveAuthorization } from "./modules/security/default-sensitive-authorization.js";
import { canonicalizeIntent } from "./modules/security/intent-binding.js";
import { createSecurityRouter } from "./modules/security/security-routes.js";
import { createWalletRouter } from "./modules/wallet/wallet-routes.js";
import type { SessionRepository, SessionRecord } from "./modules/session/session-repository.js";
import type { SecurityRepository, StepUpChallenge } from "./modules/security/security-repository.js";
import type { WalletRepository } from "./modules/wallet/wallet-repository.js";
import type { WalletTransferRepository, WalletTransferResult } from "./modules/wallet/wallet-transfer-repository.js";
import type { AuthorizationProof } from "./modules/security/sensitive-authorization.js";

// ---------------------------------------------------------------------------
// Stage R connected-journey wiring: REAL services everywhere the production
// app composes them; only the durable edges (sessions, security store, wallets)
// are in-memory fakes that enforce the same invariants their Postgres
// counterparts guarantee (revocation predicates, consume-once challenges,
// single-use transfer references).
// ---------------------------------------------------------------------------

// -- Session store: mirrors postgres-session-repository predicates ----------
function sessionStore() {
  const rows = new Map<string, SessionRecord & { revokedAt: Date | null }>();
  const repo: SessionRepository = {
    async create(input) {
      const record: SessionRecord & { revokedAt: Date | null } = { id: randomUUID(), userId: input.userId, deviceId: input.deviceId, expiresAt: input.expiresAt, revokedAt: null };
      rows.set(record.id, record);
      return { ...record };
    },
    async findActiveByRefreshHash() { throw new Error("not exercised in this journey"); },
    async rotate() { throw new Error("not exercised in this journey"); },
    async isActive(sessionId, userId, now) {
      const row = rows.get(sessionId);
      return !!row && row.userId === userId && row.revokedAt === null && row.expiresAt > now;
    },
    async revoke(sessionId, revokedAt) {
      const row = rows.get(sessionId);
      if (row && row.revokedAt === null) row.revokedAt = revokedAt;
    }
  };
  return { repo, rows };
}

// -- Security store: mirrors the consume-once challenge + revocation checks -
function securityStore() {
  const challenges = new Map<string, StepUpChallenge & { attempts: number; expiresAt: Date; consumed: boolean }>();
  const activeDevices = new Set<string>();
  const events: Array<{ eventType: string; metadata?: Record<string, unknown> }> = [];
  const repo: SecurityRepository = {
    async isActiveDevice(userId, deviceId) { return activeDevices.has(`${userId}:${deviceId}`); },
    async createChallenge(input) {
      const id = randomUUID();
      challenges.set(id, { id, userId: input.userId, deviceId: input.deviceId, purpose: input.purpose, challengeHash: input.challengeHash, intentHash: input.intentHash ?? null, attempts: 0, expiresAt: input.expiresAt, consumed: false });
    },
    async findActiveChallenge(userId, purpose) {
      for (const c of challenges.values()) {
        if (c.userId === userId && c.purpose === purpose && !c.consumed && c.expiresAt > new Date()) return { ...c };
      }
      return null;
    },
    async incrementChallengeAttempt(id) { const c = challenges.get(id); if (c) c.attempts += 1; },
    async consumeChallenge(id) { const c = challenges.get(id); if (!c || c.consumed) return false; c.consumed = true; return true; },
    async recordEvent(input) { events.push({ eventType: input.eventType, metadata: input.metadata }); }
  };
  const deviceKeys = new Map<string, string>(); // `${userId}:${deviceId}` -> public PEM
  return {
    repo, events, activeDevices, deviceKeys,
    async enroll(userId: string, deviceId: string, publicKey: string) {
      activeDevices.add(`${userId}:${deviceId}`);
      deviceKeys.set(`${userId}:${deviceId}`, publicKey);
    },
    activeKey(userId: string, deviceId: string): string | null { return deviceKeys.get(`${userId}:${deviceId}`) ?? null; }
  };
}

// -- Wallet edges ------------------------------------------------------------
function walletEdges(calls: string[]) {
  const balances = new Map<string, number>();
  const usedReferences = new Set<string>();
  const wallets: WalletRepository = {
    async getOrCreate(userId) { if (!balances.has(userId)) balances.set(userId, 0); return { userId, currency: "NGN", balanceMinor: balances.get(userId)!, updatedAt: new Date().toISOString() }; },
    async listTransactions() { return []; },
    async credit(userId, amountMinor, reference) { calls.push("credit"); balances.set(userId, (balances.get(userId) ?? 0) + amountMinor); return { id: "t", userId, type: "credit", amountMinor, balanceAfterMinor: balances.get(userId)!, reference, description: null, createdAt: new Date().toISOString() }; },
    async debit(userId, amountMinor, reference) { calls.push("debit"); balances.set(userId, (balances.get(userId) ?? 0) - amountMinor); return { id: "t", userId, type: "debit", amountMinor, balanceAfterMinor: balances.get(userId)!, reference, description: null, createdAt: new Date().toISOString() }; }
  };
  const transfers: WalletTransferRepository = {
    async transfer(input): Promise<WalletTransferResult> {
      calls.push("transfer");
      if (usedReferences.has(input.reference)) throw new Error("WALLET_REFERENCE_REUSED");
      usedReferences.add(input.reference);
      return { transferId: randomUUID(), ...input, currency: "NGN", status: "completed", createdAt: new Date().toISOString() };
    }
  };
  return { wallets, transfers, balances };
}

// -- Device key helpers (same primitives the mobile app uses) ----------------
function deviceKey() {
  const { publicKey, privateKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const spki = publicKey.export({ type: "spki", format: "pem" }).toString();
  const sign = (value: string) => { const s = createSign("SHA256"); s.update(value); s.end(); return s.sign(privateKey, "base64url" as any) as string; };
  return { spki, sign };
}

// -- App wiring that mirrors server.ts composition --------------------------
function buildApp(security: ReturnType<typeof securityStore>, sessions: ReturnType<typeof sessionStore>["repo"], transfers: WalletTransferRepository, wallets: WalletRepository) {
  const accessSecret = "test-access-secret-journey";
  const refreshTokenPepper = "test-pepper";
  const sessionService = new SessionService(sessions, refreshTokenPepper, accessSecret);
  const securityService = new SecurityService(security.repo);
  // The proof service consults the enrolled device key through the repo in
  // production; here the fake store exposes the enrolled key directly.
  (security.repo as any).getActiveDevicePublicKey = async (userId: string, deviceId: string) => security.activeKey(userId, deviceId);
  const proofs = new DeviceProofService(security.repo as never);
  const authorization = new DefaultSensitiveAuthorization(proofs);

  const app = express();
  app.use(requestId);
  app.use(express.json({ limit: "32kb" }));
  app.use(createRequireAuth(accessSecret, sessions));
  app.use("/security", createSecurityRouter(securityService));
  app.use("/wallet", createWalletRouter(wallets, transfers, authorization));
  app.use(errorHandler);
  return app;
}

async function listen(app: express.Express) {
  const server = await new Promise<import("node:http").Server>((resolve) => {
    const s = app.listen(0, "127.0.0.1", () => resolve(s));
  });
  const { port } = server.address() as AddressInfo;
  return { url: `http://127.0.0.1:${port}`, close: () => new Promise<void>((resolve) => server.close(() => resolve())) };
}

test("Stage R journey: session → step-up → device proof → wallet transfer, then attack the chain", async () => {
  const { repo: sessions, rows } = sessionStore();
  const security = securityStore();
  const calls: string[] = [];
  const { wallets, transfers } = walletEdges(calls);
  const app = buildApp(security, sessions, transfers, wallets);
  const srv = await listen(app);

  try {
    // -- 1. Session establishment (real SessionService, real JWT) ----------
    const session = await new SessionService(sessions, "test-pepper", "test-access-secret-journey").create("user-A", "device-1");
    assert.ok(session.accessToken.length > 20);
    const bearer = { authorization: `Bearer ${session.accessToken}`, "content-type": "application/json" };

    // -- 2. Anonymous attacker is locked out of every protected route ------
    const anon = await fetch(`${srv.url}/wallet`, { method: "GET" });
    assert.equal(anon.status, 401);

    // -- 3. Wallet balance is visible only to the authenticated owner ------
    const balance = await fetch(`${srv.url}/wallet`, { headers: bearer });
    assert.equal(balance.status, 200);
    assert.equal((await balance.json()).balanceMinor, 0);

    // -- 4. Step-up challenge requires an ACTIVE device --------------------
    const stepUpNoDevice = await fetch(`${srv.url}/security/step-up/challenge`, { method: "POST", headers: bearer, body: JSON.stringify({ purpose: "wallet_transfer", deviceId: "device-1" }) });
    assert.equal(stepUpNoDevice.status, 403); // DEVICE_NOT_ACTIVE
    await security.enroll("user-A", "device-1", deviceKey().spki);

    // -- 5. Challenge issuance and bound-intent proof ----------------------
    const intent = { toUserId: "user-B", amountMinor: 25000, currency: "NGN" as const, reference: `ref-${randomUUID()}` };
    const stepUp = await fetch(`${srv.url}/security/step-up/challenge`, { method: "POST", headers: bearer, body: JSON.stringify({ purpose: "wallet_transfer", deviceId: "device-1", intent }) });
    assert.equal(stepUp.status, 201);
    const { challenge, expiresAt } = await stepUp.json();
    assert.ok(challenge.length >= 40);
    assert.ok(new Date(expiresAt) > new Date());

    // -- 6. Transfer with a signature over the WRONG message is rejected ---
    const key = deviceKey();
    await security.enroll("user-A", "device-1", key.spki);
    const wrongSig = await fetch(`${srv.url}/wallet/transfer`, { method: "POST", headers: bearer, body: JSON.stringify({ ...intent, deviceId: "device-1", challenge, signature: key.sign("totally-different-message") }) });
    assert.equal(wrongSig.status, 401); // DEVICE_PROOF_INVALID

    // -- 7. Correct device signature completes the transfer ----------------
    const proof: AuthorizationProof = {
      deviceId: "device-1",
      challenge,
      signature: key.sign(`${challenge}.${canonicalizeIntent(intent)}`)
    };
    const ok = await fetch(`${srv.url}/wallet/transfer`, { method: "POST", headers: bearer, body: JSON.stringify({ ...intent, ...proof }) });
    assert.equal(ok.status, 201);
    const transfer = await ok.json();
    assert.equal(transfer.status, "completed");
    assert.equal(transfer.amountMinor, 25000);
    assert.ok(calls.includes("transfer"));

    // -- 8. Replay the SAME proof for a different amount: fail closed ------
    const replay = await fetch(`${srv.url}/wallet/transfer`, { method: "POST", headers: bearer, body: JSON.stringify({ ...intent, amountMinor: 99999999, deviceId: "device-1", challenge, signature: proof.signature }) });
    assert.equal(replay.status, 401); // challenge consumed + intent mismatch

    // -- 9. Replaying the exact winning request also fails (single use) ----
    const exactReplay = await fetch(`${srv.url}/wallet/transfer`, { method: "POST", headers: bearer, body: JSON.stringify({ ...intent, ...proof }) });
    assert.equal(exactReplay.status, 401); // challenge already consumed

    // -- 10. Another user cannot present a proof for user A's challenge ----
    const sessionB = await new SessionService(sessions, "test-pepper", "test-access-secret-journey").create("user-B", "device-2");
    const bearerB = { authorization: `Bearer ${sessionB.accessToken}`, "content-type": "application/json" };
    const crossUser = await fetch(`${srv.url}/security/step-up/challenge`, { method: "POST", headers: bearerB, body: JSON.stringify({ purpose: "wallet_transfer", deviceId: "device-1", intent }) });
    assert.equal(crossUser.status, 403); // device-1 does not belong to user B

    // -- 11. Revoked session is locked out immediately (real revocation) ---
    await sessions.revoke(session.sessionId, new Date());
    const afterRevoke = await fetch(`${srv.url}/wallet`, { headers: bearer });
    assert.equal(afterRevoke.status, 401);
    const afterRevokeTransfer = await fetch(`${srv.url}/wallet/transfer`, { method: "POST", headers: bearer, body: JSON.stringify({ ...intent, ...proof }) });
    assert.equal(afterRevokeTransfer.status, 401);
  } finally { await srv.close(); }
});
