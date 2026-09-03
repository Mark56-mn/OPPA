import { randomUUID } from "node:crypto";
import { generateOtp, hashOtp } from "./otp-crypto.js";
import { otpPolicy } from "./otp-policy.js";
import type { OtpRepository } from "./otp-repository.js";
import type { SmsProvider } from "../sms/types.js";
import type { RiskService } from "../risk/risk-service.js";

export class OtpService {
  constructor(
    private readonly repository: OtpRepository,
    private readonly sms: SmsProvider,
    private readonly pepper: string,
    private readonly senderId: string,
    private readonly callbackUrl?: string,
    private readonly risk?: RiskService
  ) {}

  async request(phone: string, now = new Date()): Promise<{ challengeId: string }> {
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
      const result = await this.sms.send({
        to: phone,
        message: `Your OPPA verification code is ${otp}. It expires in 5 minutes.`,
        senderId: this.senderId,
        callbackUrl: this.callbackUrl
      });

      if (result.providerMessageId) {
        await this.repository.setProviderMessageId(challenge.id, result.providerMessageId);
      }

      return { challengeId: challenge.id };
    } catch (error) {
      await this.repository.consume(challenge.id, now);
      throw error;
    }
  }

  async verify(phone: string, otp: string, now = new Date()): Promise<void> {
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
