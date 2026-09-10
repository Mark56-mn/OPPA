import assert from "node:assert/strict";
import test from "node:test";
import { OtpService } from "../otp/otp-service.js";
import type { OtpRepository } from "../otp/otp-repository.js";
import type { SmsProvider } from "../sms/types.js";

function otpRepo(): OtpRepository & { attempts: number; consumeCalls: number } {
  const state = { attempts: 0, consumeCalls: 0 };
  return {
    ...state,
    async invalidateActive() {},
    async getLatestCreatedAt() { return null; },
    async countCreatedSince() { return 0; },
    async create() {},
    async setProviderMessageId() {},
    async getActive() { return null; },
    async consume() { state.consumeCalls += 1; },
    async incrementAttempts() { return ++state.attempts; }
  } as OtpRepository & { attempts: number; consumeCalls: number };
}

const sms: SmsProvider = {
  name: "test",
  async send() { return { provider: "test", outcome: "accepted" as const, providerMessageId: "msg-1" }; }
};

test("OTP verify rejects malformed code shapes before any repository access", async () => {
  const repo = otpRepo();
  const service = new OtpService(repo, sms, "pepper-aaa", undefined);
  // Non-6-digit shapes must fail fast without touching the challenge store.
  for (const bad of ["", "12345", "1234567", "abcdef", "12 456", "+123456"]) {
    await assert.rejects(() => service.verify("+2348012345678", bad), /OTP_INVALID_OR_EXPIRED/);
  }
  assert.equal(repo.attempts, 0, "no attempt increment may run for malformed codes");
  assert.equal(repo.consumeCalls, 0, "no consumption may run for malformed codes");
});
