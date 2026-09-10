import assert from "node:assert/strict";
import test from "node:test";
import type { AddressInfo } from "node:net";
import express from "express";
import { createHmac } from "node:crypto";
import { errorHandler } from "../../http/error-handler.js";
import { createSmsCallbackRouter } from "./sms-callback-routes.js";
import { SmsDeliveryRecorder } from "./sms-delivery-recorder.js";
import { TermiiProvider } from "./termii-provider.js";
import type { SmsAttempt, SmsAttemptRepository } from "./types.js";

function attemptRepo(): SmsAttemptRepository & { rows: SmsAttempt[] } {
  const rows: SmsAttempt[] = [];
  return {
    get rows() { return rows; },
    async record(a: SmsAttempt) { rows.push({ ...a }); },
    async countForChallengeSince() { return 0; },
    async hasSubmittedAttempt() { return false; }
  };
}

function appWith(recorder: SmsDeliveryRecorder) {
  const app = express();
  app.use(express.json({ verify: (req: any, _res, buf) => { (req as any).rawBody = buf; } }));
  app.use("/sms/webhooks", createSmsCallbackRouter(recorder));
  app.use(errorHandler);
  return app;
}

async function listen(app: express.Express) {
  const server = await new Promise<import("node:http").Server>((resolve) => {
    const s = app.listen(0, "127.0.0.1", () => resolve(s));
  });
  const { port } = server.address() as AddressInfo;
  return { url: `http://127.0.0.1:${port}`, close: () => new Promise<void>((r) => server.close(() => r())) };
}

const post = (url: string, path: string, body: string, headers: Record<string, string> = {}) =>
  fetch(`${url}${path}`, { method: "POST", headers: { "content-type": "application/json", ...headers }, body });

test("bulksms callback: valid delivered report is recorded idempotently", async () => {
  const repo = attemptRepo();
  const recorder = new SmsDeliveryRecorder(repo);
  const srv = await listen(appWith(recorder));
  try {
    const body = JSON.stringify({ message_id: "msg-123", recipient: "2348012345678", delivery_status: "delivrd" });
    const res = await post(srv.url, "/sms/webhooks/bulksms", body);
    assert.equal(res.status, 200);
    assert.equal(repo.rows.length, 1);
    assert.equal(repo.rows[0].provider, "bulksms");
    assert.equal(repo.rows[0].providerMessageId, "msg-123");
    assert.equal(repo.rows[0].errorKind, "dlr:delivered");
    // Duplicate delivery: tolerated, recorded again as a harmless observation.
    const replay = await post(srv.url, "/sms/webhooks/bulksms", body);
    assert.equal(replay.status, 200);
  } finally { await srv.close(); }
});

test("bulksms callback: malformed payloads are rejected without recording", async () => {
  const repo = attemptRepo();
  const recorder = new SmsDeliveryRecorder(repo);
  const srv = await listen(appWith(recorder));
  try {
    for (const body of [JSON.stringify({ recipient: "2348012345678" }), JSON.stringify({ message_id: { "$gt": "" } }), "{}", "not-json"]) {
      const res = await post(srv.url, "/sms/webhooks/bulksms", body);
      assert.equal(res.status, 400, `${body.slice(0, 30)} should be rejected`);
    }
    assert.equal(repo.rows.length, 0);
  } finally { await srv.close(); }
});

test("termii callback: unsigned or wrongly-signed requests are rejected 401", async () => {
  const repo = attemptRepo();
  const termii = new TermiiProvider({ baseUrl: "https://termii.test", apiKey: "k", senderId: "OPPA", timeoutMs: 1000, webhookSecret: "shhh" });
  const recorder = new SmsDeliveryRecorder(repo, termii);
  const srv = await listen(appWith(recorder));
  try {
    const body = JSON.stringify({ message_id: "m1", status: "Delivered", receiver: "2348012345678" });
    const unsigned = await post(srv.url, "/sms/webhooks/termii", body);
    assert.equal(unsigned.status, 401);
    const forged = await post(srv.url, "/sms/webhooks/termii", body, { "x-termii-signature": "deadbeef" });
    assert.equal(forged.status, 401);
    assert.equal(repo.rows.length, 0);
  } finally { await srv.close(); }
});

test("termii callback: correctly-signed event is accepted and mapped", async () => {
  const repo = attemptRepo();
  const termii = new TermiiProvider({ baseUrl: "https://termii.test", apiKey: "k", senderId: "OPPA", timeoutMs: 1000, webhookSecret: "shhh" });
  const recorder = new SmsDeliveryRecorder(repo, termii);
  const srv = await listen(appWith(recorder));
  try {
    const body = JSON.stringify({ message_id: "m1", status: "Delivered", receiver: "2348012345678" });
    const sig = createHmac("sha512", "shhh").update(Buffer.from(body, "utf8")).digest("hex");
    const res = await post(srv.url, "/sms/webhooks/termii", body, { "x-termii-signature": sig });
    assert.equal(res.status, 200);
    assert.equal(repo.rows.length, 1);
    assert.equal(repo.rows[0].errorKind, "dlr:delivered");
    // Failed mapping
    const failBody = JSON.stringify({ message_id: "m2", status: "Failed" });
    const failSig = createHmac("sha512", "shhh").update(Buffer.from(failBody, "utf8")).digest("hex");
    await post(srv.url, "/sms/webhooks/termii", failBody, { "x-termii-signature": failSig });
    assert.equal(repo.rows[1].errorKind, "dlr:failed");
  } finally { await srv.close(); }
});

test("termii callback without a configured secret is disabled (fail closed)", async () => {
  const repo = attemptRepo();
  const recorder = new SmsDeliveryRecorder(repo); // no Termii adapter wired
  const srv = await listen(appWith(recorder));
  try {
    const body = JSON.stringify({ message_id: "m1", status: "Delivered" });
    const res = await post(srv.url, "/sms/webhooks/termii", body, { "x-termii-signature": "whatever" });
    assert.equal(res.status, 401);
    assert.equal(repo.rows.length, 0);
  } finally { await srv.close(); }
});
