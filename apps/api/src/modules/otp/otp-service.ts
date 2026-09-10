import { randomUUID } from "node:crypto";
import { generateOtp, hashOtp } from "./otp-crypto.js";
import { otpPolicy } from "./otp-policy.js";
import type { OtpRepository } from "./otp-repository.js";
import type { SendSmsInput, SmsProvider } from "../sms/types.js";
import type { RiskService } from "../risk/risk-service.js";

export type OtpDeliveryState = "submitted" | "unknown";

/**
 * Authentication depends only on a normalized SMS port — it never knows
 * whether BulkSMS or Termii delivered the OTP, never sees provider config
 * (sender IDs, callback URLs, keys), and provider failover happens inside
 * the gateway without generating a second OTP.
 */
export class OtpService {
  constructor(
    private readonly repository: OtpRepository,
    private readonly sms: SmsProvider,
    private readonly pepper: string,
    private readonly risk?: RiskService
  ) {}

  async request(phone: string, now = new Date()): Promise<{ challengeId: string; delivery: OtpDeliveryState }> {
    const active = await this.repository.getActive(phone, now);
    if (active) throw new Error("OTP_ALREADY_ACTIVE");

    const latest = await this.repository.getLatestCreatedAt(phone);
    if (latest && (now.getTime() - latest.getTime()) / 1000 < otpPolicy.requestCooldownSeconds) {
      await this.recordOtpAbuse(phone, "request_cooldown");
      throw new Error("OTP_RATE_LIMITED");
    }

    const hourlyCount = await this.repository.countCreatedSince(
      phone,
      new Date(now.getTime() - 60 * 60 * 1000)
    );
    if (hourlyCount >= otpPolicy.maxRequestsPerHour) {
      await this.recordOtpAbuse(phone, "hourly_limit_exceeded");
      throw new Error("OTP_RATE_LIMITED");
    }

    const otp = generateOtp();
    const challenge = {
      id: randomUUID(),
      phone,
      otpHash: hashOtp(phone, otp, this.pepper),
      expiresAt: new Date(now.getTime() + otpPolicy.ttlSeconds * 1000),
      attempts: 0,
      consumedAt: null,
      providerMessageId: null
    };

    await this.repository.invalidateActive(phone, now);
    await this.repository.create(challenge);

    try {
      const input: SendSmsInput = {
        to: phone,
        message: `Your OPPA verification code is ${otp}. It expires in 5 minutes.`
      };
      const result = await this.sms.send(input);

      if (result.outcome === "accepted") {
        if (result.providerMessageId) {
          await this.repository.setProviderMessageId(challenge.id, result.providerMessageId);
        }
        return { challengeId: challenge.id, delivery: "submitted" };
      }

      if (result.outcome === "unknown") {
        // Ambiguous (timeout/network/malformed response): an SMS MAY still be
        // in flight. NEVER burn the challenge here — the user may receive the
        // code and verification must remain possible. Also never auto-resend:
        // duplicate delivery is prevented by not re-sending on ambiguity; the
        // user can explicitly request a new challenge after the cooldown.
        return { challengeId: challenge.id, delivery: "unknown" };
      }

      // Definitive provider rejection (every configured provider failed).
      await this.repository.consume(challenge.id, now);
      if (result.error?.providerCode === "SMS_GATEWAY_UNCONFIGURED") {
        throw new Error("SMS_GATEWAY_UNCONFIGURED");
      }
      throw new Error("SMS_DELIVERY_FAILED");
    } catch (error) {
      if ((error as Error).message === "SMS_DELIVERY_FAILED") throw error;
      // Defensive: an adapter threw outside the normalized outcome contract.
      // Burn the challenge so an unsent OTP cannot linger as "active".
      await this.repository.consume(challenge.id, now);
      throw error;
    }
  }

  async verify(phone: string, otp: string, now = new Date()): Promise<void> {
    // Defense-in-depth shape guard: the route layer already enforces this, but
    // verification must fail fast on malformed input regardless of call path.
    if (!/^\d{6}$/.test(otp)) throw new Error("OTP_INVALID_OR_EXPIRED");
    const challenge = await this.repository.getActive(phone, now);
    if (!challenge || challenge.expiresAt <= now || challenge.consumedAt) {
      throw new Error("OTP_INVALID_OR_EXPIRED");
    }
    if (challenge.attempts >= otpPolicy.maxVerificationAttempts) {
      await this.recordOtpAbuse(phone, "attempts_exceeded");
      throw new Error("OTP_ATTEMPTS_EXCEEDED");
    }

    const attempts = await this.repository.incrementAttempts(challenge.id);
    if (attempts > otpPolicy.maxVerificationAttempts) {
      await this.recordOtpAbuse(phone, "attempts_exceeded");
      throw new Error("OTP_ATTEMPTS_EXCEEDED");
    }

    if (hashOtp(phone, otp, this.pepper) !== challenge.otpHash) {
      throw new Error("OTP_INVALID_OR_EXPIRED");
    }

    await this.repository.consume(challenge.id, now);
  }

  private async recordOtpAbuse(phone: string, signal: string) {
    try {
      await this.risk?.recordEvent({
        category: "otp_abuse",
        signal,
        score: 40,
        decision: "review",
        reasons: [signal],
        metadata: { phone }
      });
    } catch {}
  }
}
