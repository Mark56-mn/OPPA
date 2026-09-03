import { strict as assert } from "node:assert";
import test from "node:test";
import { OtpService } from "./otp-service.js";
import type { OtpChallenge, OtpRepository } from "./otp-repository.js";
import type { SendSmsInput, SendSmsResult, SmsProvider } from "../sms/types.js";

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
  async send(input: SendSmsInput): Promise<SendSmsResult> {
    this.sent.push(input);
    return { provider: this.name, providerMessageId: "msg-1", status: "submitted" };
  }
}

test("OTP is never returned by request", async () => {
  const repo = new MemoryOtpRepository();
  const sms = new CapturingSms();
  const service = new OtpService(repo, sms, "pepper", "OPPA");
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
  const service = new OtpService(repo, sms, "pepper", "OPPA", undefined, risk as any);
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
