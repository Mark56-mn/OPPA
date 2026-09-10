import { strict as assert } from "node:assert";
import test from "node:test";
import { FailoverSmsGateway } from "./sms-gateway.js";
import { TermiiProvider } from "./termii-provider.js";
import { BulkSmsProvider } from "./bulksms-provider.js";
import type {
  NormalizedSmsResult,
  SendSmsInput,
  SmsAttempt,
  SmsAttemptRepository,
  SmsProvider
} from "./types.js";

type ScriptedSend = (input: SendSmsInput) => Promise<NormalizedSmsResult>;

function fakeProvider(name: string, script: ScriptedSend): SmsProvider {
  return { name, send: script };
}

function attemptRepo(): SmsAttemptRepository & { rows: SmsAttempt[] } {
  const rows: SmsAttempt[] = [];
  return {
    get rows() { return rows; },
    async record(attempt: SmsAttempt) { rows.push({ ...attempt }); },
    async countForChallengeSince(challengeId: string, since: Date) {
      return rows.filter(r => r.challengeId === challengeId && r.attemptedAt >= since).length;
    },
    async hasSubmittedAttempt(challengeId: string) {
      return rows.some(r => r.challengeId === challengeId && (r.outcome === "accepted" || r.outcome === "unknown"));
    }
  };
}

const input: SendSmsInput = { to: "+2348012345678", message: "Your OPPA verification code is 123456." };

// ---------------------------------------------------------------------------
// Gateway behavior
// ---------------------------------------------------------------------------

test("gateway: accepted on primary stops the chain (no double send)", async () => {
  const repo = attemptRepo();
  const primary = fakeProvider("primary", async () => ({ provider: "primary", outcome: "accepted", providerMessageId: "P1" }));
  const fallback = fakeProvider("fallback", async () => { throw new Error("MUST NOT BE CALLED"); });
  const gateway = new FailoverSmsGateway([primary, fallback], repo, { challengeId: "c1", maxAttemptsPerMinute: 4 });

  const result = await gateway.send(input);
  assert.equal(result.outcome, "accepted");
  assert.equal(result.providerMessageId, "P1");
  assert.equal(repo.rows.length, 1);
  assert.equal(repo.rows[0].provider, "primary");
});

test("gateway: definitive failure falls through to the fallback provider", async () => {
  const repo = attemptRepo();
  const primary = fakeProvider("primary", async () => ({ provider: "primary", outcome: "failed", error: { kind: "provider_rejected", httpStatus: 500 } }));
  const fallback = fakeProvider("fallback", async () => ({ provider: "fallback", outcome: "accepted", providerMessageId: "F1" }));
  const gateway = new FailoverSmsGateway([primary, fallback], repo, { challengeId: "c1", maxAttemptsPerMinute: 4 });

  const result = await gateway.send(input);
  assert.equal(result.outcome, "accepted");
  assert.equal(result.provider, "fallback");
  assert.deepEqual(repo.rows.map(r => r.provider), ["primary", "fallback"]);
  assert.deepEqual(repo.rows.map(r => r.outcome), ["failed", "accepted"]);
});

test("gateway: timeout on primary may fall back, but a repeated timeout consumes the budget and returns unknown", async () => {
  const repo = attemptRepo();
  const timeout = fakeProvider("flaky", async () => ({ provider: "flaky", outcome: "unknown", error: { kind: "timeout" } }));
  const gateway = new FailoverSmsGateway([timeout, timeout], repo, { challengeId: "c1", maxAttemptsPerMinute: 2 });

  const result = await gateway.send(input);
  // Unknown is never success...
  assert.equal(result.outcome, "unknown");
  // ...both providers were attempted exactly once each (no same-provider retry)...
  assert.deepEqual(repo.rows.map(r => r.provider), ["flaky", "flaky"]);
  // ...and every attempt is persisted with the timeout classification.
  assert.deepEqual(repo.rows.map(r => r.errorKind), ["timeout", "timeout"]);
});

test("gateway: durable per-challenge budget blocks further provider sends", async () => {
  const repo = attemptRepo();
  // Pre-fill the ledger: 4 attempts in the last minute.
  for (let i = 0; i < 4; i++) {
    await repo.record({ challengeId: "c-budget", provider: "primary", outcome: "unknown", errorKind: "timeout", attemptedAt: new Date() });
  }
  const sendCalls: number[] = [];
  const provider = fakeProvider("primary", async () => { sendCalls.push(1); return { provider: "primary", outcome: "accepted", providerMessageId: "x" }; });
  const gateway = new FailoverSmsGateway([provider], repo, { challengeId: "c-budget", maxAttemptsPerMinute: 4 });

  const result = await gateway.send(input);
  assert.equal(result.outcome, "failed");
  assert.equal(result.error?.providerCode, "SMS_ATTEMPT_BUDGET_EXCEEDED");
  assert.equal(sendCalls.length, 0, "budget exhaustion must prevent any provider call");
});

test("gateway: unconfigured chain fails closed and never reports success", async () => {
  const repo = attemptRepo();
  const gateway = new FailoverSmsGateway([], repo, { challengeId: "c1" });
  const result = await gateway.send(input);
  assert.equal(result.outcome, "failed");
  assert.equal(result.error?.providerCode, "SMS_GATEWAY_UNCONFIGURED");
});

test("gateway: adapter that throws is contained as unknown, never a success", async () => {
  const repo = attemptRepo();
  const throwing = fakeProvider("boom", async () => { throw new Error("socket hang up"); });
  const fallback = fakeProvider("fallback", async () => ({ provider: "fallback", outcome: "accepted", providerMessageId: "F1" }));
  const gateway = new FailoverSmsGateway([throwing, fallback], repo, { challengeId: "c1", maxAttemptsPerMinute: 4 });

  const result = await gateway.send(input);
  assert.equal(result.outcome, "accepted", "fallback should rescue the send");
  assert.equal(repo.rows[0].provider, "boom");
  assert.equal(repo.rows[0].outcome, "unknown", "thrown adapter errors are recorded as unknown");
});

// ---------------------------------------------------------------------------
// Adapter classification (mocked fetch)
// ---------------------------------------------------------------------------

const ctx = { fetch: globalThis.fetch };

test("bulksms adapter: 200 + success payload yields accepted with message id", async () => {
  globalThis.fetch = (async () => new Response(JSON.stringify({
    status: "success", code: "BSNG-0000", message: "Message sent successfully",
    data: { message_id: "a22f907b-c5aa-44e4-89e4-06fe253e9cbb", recipients_count: 1 }
  }), { status: 200 })) as unknown as typeof fetch;
  try {
    const provider = new BulkSmsProvider({ baseUrl: "https://bulksms.test", apiToken: "tok", senderId: "OPPA", timeoutMs: 1000 });
    const result = await provider.send(input);
    assert.equal(result.outcome, "accepted");
    assert.equal(result.providerMessageId, "a22f907b-c5aa-44e4-89e4-06fe253e9cbb");
  } finally { globalThis.fetch = ctx.fetch; }
});

test("bulksms adapter: provider error payload is a definitive failure", async () => {
  globalThis.fetch = (async () => new Response(JSON.stringify({ status: "error", code: "BSNG-0101", message: "invalid sender id" }), { status: 400 })) as unknown as typeof fetch;
  try {
    const provider = new BulkSmsProvider({ baseUrl: "https://bulksms.test", apiToken: "tok", senderId: "OPPA", timeoutMs: 1000 });
    const result = await provider.send(input);
    assert.equal(result.outcome, "failed");
    assert.equal(result.error?.kind, "provider_rejected");
    assert.equal(result.error?.providerCode, "BSNG-0101");
  } finally { globalThis.fetch = ctx.fetch; }
});

test("termii adapter: dnd channel body and ok-code success mapping", async () => {
  let captured: { url: string; init: RequestInit } | null = null;
  globalThis.fetch = (async (url: any, init: any) => {
    captured = { url: String(url), init };
    return new Response(JSON.stringify({ code: "ok", message_id: "3017544054459083819856413", message: "Successfully Sent" }), { status: 200 });
  }) as unknown as typeof fetch;
  try {
    const provider = new TermiiProvider({ baseUrl: "https://termii.test", apiKey: "k", senderId: "OPPA", timeoutMs: 1000 });
    const result = await provider.send(input);
    assert.equal(result.outcome, "accepted");
    assert.equal(result.providerMessageId, "3017544054459083819856413");
    const body = JSON.parse(String(captured!.init.body));
    assert.equal(body.channel, "dnd", "OTP messages must use the transactional dnd route");
    assert.equal(body.to, "2348012345678");
    assert.equal(captured!.url, "https://termii.test/api/sms/send");
  } finally { globalThis.fetch = ctx.fetch; }
});

test("termii adapter: 200 with error code is a definitive failure, not success", async () => {
  globalThis.fetch = (async () => new Response(JSON.stringify({ code: "99", message: "insufficient balance" }), { status: 200 })) as unknown as typeof fetch;
  try {
    const provider = new TermiiProvider({ baseUrl: "https://termii.test", apiKey: "k", senderId: "OPPA", timeoutMs: 1000 });
    const result = await provider.send(input);
    assert.equal(result.outcome, "failed");
    assert.equal(result.error?.kind, "provider_rejected");
  } finally { globalThis.fetch = ctx.fetch; }
});

test("termii adapter: ambiguous response (ok without message id) is unknown", async () => {
  globalThis.fetch = (async () => new Response(JSON.stringify({ code: "ok", message: "Successfully Sent" }), { status: 200 })) as unknown as typeof fetch;
  try {
    const provider = new TermiiProvider({ baseUrl: "https://termii.test", apiKey: "k", senderId: "OPPA", timeoutMs: 1000 });
    const result = await provider.send(input);
    assert.equal(result.outcome, "unknown", "missing message id must never be success");
    assert.equal(result.error?.kind, "ambiguous_response");
  } finally { globalThis.fetch = ctx.fetch; }
});

test("adapters: timeout classifies as unknown, not failed", async () => {
  globalThis.fetch = (async (_url: any, init: any) => {
    return await new Promise((_resolve, reject) => {
      (init?.signal as AbortSignal).addEventListener("abort", () => {
        const e = new Error("The operation was aborted");
        (e as any).name = "AbortError";
        reject(e);
      });
    });
  }) as unknown as typeof fetch;
  try {
    const provider = new TermiiProvider({ baseUrl: "https://termii.test", apiKey: "k", senderId: "OPPA", timeoutMs: 20 });
    const result = await provider.send(input);
    assert.equal(result.outcome, "unknown");
    assert.equal(result.error?.kind, "timeout");
  } finally { globalThis.fetch = ctx.fetch; }
});
