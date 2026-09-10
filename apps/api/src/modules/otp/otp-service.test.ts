import { strict as assert } from "node:assert";
import test from "node:test";
import { OtpService } from "./otp-service.js";
import type { OtpChallenge, OtpRepository } from "./otp-repository.js";
import type { NormalizedSmsResult, SendSmsInput, SmsProvider } from "../sms/types.js";

class MemoryOtpRepository implements OtpRepository {
  rows: OtpChallenge[] = [];
  async invalidateActive(phone: string, now: Date) {
    for (const row of this.rows) if (row.phone === phone && !row.consumedAt) row.consumedAt = now;
  }
  async getLatestCreatedAt(phone: string) {
    const row = this.rows.filter(x => x.phone === phone).sort((a,b) => b.expiresAt.getTime()-a.expiresAt.getTime())[0];
    return row ? new Date(row.expiresAt.getTime() - 300_000) : null;
  }
  async countCreatedSince(phone: string, since: Date) {
    return this.rows.filter(x => x.phone === phone && x.expiresAt.getTime() - 300_000 >= since.getTime()).length;
  }
  async create(c: OtpChallenge) { this.rows.push({...c}); }
  async setProviderMessageId(id: string, value: string) { const row=this.rows.find(x=>x.id===id); if(row) row.providerMessageId=value; }
  async getActive(phone: string, now: Date) { return this.rows.find(x=>x.phone===phone && !x.consumedAt && x.expiresAt>now) ?? null; }
  async consume(id: string, now: Date) { const row=this.rows.find(x=>x.id===id); if(row) row.consumedAt=now; }
  async incrementAttempts(id: string) { const row=this.rows.find(x=>x.id===id); if(!row) throw new Error("OTP_INVALID_OR_EXPIRED"); row.attempts++; return row.attempts; }
}

class CapturingSms implements SmsProvider {
  readonly name = "test-provider";
  sent: SendSmsInput[] = [];
  result: NormalizedSmsResult = { provider: "test-provider", outcome: "accepted", providerMessageId: "msg-1" };
  async send(input: SendSmsInput): Promise<NormalizedSmsResult> {
    this.sent.push(input);
    return this.result;
  }
}

test("OTP is never returned by request", async () => {
  const repo = new MemoryOtpRepository();
  const sms = new CapturingSms();
  const service = new OtpService(repo, sms, "pepper");
  const result = await service.request("+2348012345678", new Date("2026-01-01T00:00:00Z"));
  assert.ok(result.challengeId);
  assert.equal("otp" in result, false);
  assert.match(sms.sent[0].message, /OPPA verification code is \d{6}/);
});

test("records an OTP abuse event when rate limited", async () => {
  const repo = new MemoryOtpRepository();
  const sms = new CapturingSms();
  const events: any[] = [];
  const risk = { recordEvent: async (input: any) => { events.push(input); } };
  const service = new OtpService(repo, sms, "pepper", risk as any);
  const first = await service.request("+2348012345678", new Date("2026-01-01T00:00:00Z"));
  // A consumed challenge (verified or SMS-failure path) leaves the cooldown
  // branch reachable; an unconsumed one short-circuits to OTP_ALREADY_ACTIVE.
  await repo.consume(first.challengeId, new Date("2026-01-01T00:00:30Z"));
  await assert.rejects(
    service.request("+2348012345678", new Date("2026-01-01T00:00:30Z")),
    { message: "OTP_RATE_LIMITED" }
  );
  assert.equal(events.length, 1);
  assert.equal(events[0].category, "otp_abuse");
  assert.equal(events[0].signal, "request_cooldown");
  assert.deepEqual(events[0].metadata, { phone: "+2348012345678" });
});

test("challenge survives gateway ambiguity (unknown never burns the OTP)", async () => {
  const repo = new MemoryOtpRepository();
  const sms = new CapturingSms();
  sms.result = { provider: "test-provider", outcome: "unknown", error: { kind: "timeout" } };
  const service = new OtpService(repo, sms, "pepper");
  const now = new Date("2026-01-01T00:00:00Z");
  const result = await service.request("+2348012345678", now);
  assert.equal(result.delivery, "unknown");
  // The challenge must remain verifiable: an SMS may still be in flight.
  const active = await repo.getActive("+2348012345678", now);
  assert.ok(active, "ambiguous delivery must NOT consume the challenge");
  assert.equal(active!.id, result.challengeId);
});

test("definitive provider failure consumes the challenge and fails loudly", async () => {
  const repo = new MemoryOtpRepository();
  const sms = new CapturingSms();
  sms.result = { provider: "test-provider", outcome: "failed", error: { kind: "provider_rejected", httpStatus: 400 } };
  const service = new OtpService(repo, sms, "pepper");
  const now = new Date("2026-01-01T00:00:00Z");
  await assert.rejects(service.request("+2348012345678", now), { message: "SMS_DELIVERY_FAILED" });
  const active = await repo.getActive("+2348012345678", now);
  assert.equal(active, null, "no SMS went out, so no active challenge may linger");
});

test("accepted delivery stores the provider message id on the challenge", async () => {
  const repo = new MemoryOtpRepository();
  const sms = new CapturingSms();
  const service = new OtpService(repo, sms, "pepper");
  const result = await service.request("+2348012345678", new Date("2026-01-01T00:00:00Z"));
  assert.equal(result.delivery, "submitted");
  const active = await repo.getActive("+2348012345678", new Date("2026-01-01T00:00:01Z"));
  assert.equal(active!.providerMessageId, "msg-1");
});

test("unconfigured gateway maps to SMS_GATEWAY_UNCONFIGURED, not a generic error", async () => {
  const repo = new MemoryOtpRepository();
  const sms = new CapturingSms();
  sms.result = { provider: "failover-gateway", outcome: "failed", error: { kind: "provider_rejected", providerCode: "SMS_GATEWAY_UNCONFIGURED" } };
  const service = new OtpService(repo, sms, "pepper");
  await assert.rejects(service.request("+2348012345678", new Date("2026-01-01T00:00:00Z")), { message: "SMS_GATEWAY_UNCONFIGURED" });
});
