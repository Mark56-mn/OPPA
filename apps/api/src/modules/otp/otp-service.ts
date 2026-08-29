import { randomUUID } from "node:crypto";
import { generateOtp, hashOtp } from "./otp-crypto.js";
import { otpPolicy } from "./otp-policy.js";
import type { OtpRepository } from "./otp-repository.js";
import type { SmsProvider } from "../sms/types.js";

export class OtpService {
  constructor(
    private readonly repository: OtpRepository,
    private readonly sms: SmsProvider,
    private readonly pepper: string,
    private readonly senderId: string,
    private readonly callbackUrl?: string
  ) {}

  async request(phone: string, now = new Date()): Promise<{ challengeId: string }> {
    const active = await this.repository.getActive(phone, now);
    if (active) {
      const secondsLeft = Math.max(1, Math.ceil((active.expiresAt.getTime() - now.getTime()) / 1000));
      throw new Error(`OTP_ALREADY_ACTIVE:${secondsLeft}`);
    }

    const latest = await this.repository.getLatestCreatedAt(phone);
    if (latest) {
      const secondsSinceLast = (now.getTime() - latest.getTime()) / 1000;
      if (secondsSinceLast < otpPolicy.requestCooldownSeconds) {
        throw new Error("OTP_RATE_LIMITED");
      }
    }

    const hourlyCount = await this.repository.countCreatedSince(
      phone,
      new Date(now.getTime() - 60 * 60 * 1000)
    );
    if (hourlyCount >= otpPolicy.maxRequestsPerHour) {
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
      throw new Error("OTP_ATTEMPTS_EXCEEDED");
    }

    const attempts = await this.repository.incrementAttempts(challenge.id);
    if (attempts > otpPolicy.maxVerificationAttempts) {
      throw new Error("OTP_ATTEMPTS_EXCEEDED");
    }

    const expected = hashOtp(phone, otp, this.pepper);
    if (expected !== challenge.otpHash) {
      throw new Error("OTP_INVALID_OR_EXPIRED");
    }

    await this.repository.consume(challenge.id, now);
  }
}
