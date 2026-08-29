import { OtpService } from "../otp/otp-service.js";
import { normalizePhone } from "../identity/phone.js";
import type { IdentityRepository } from "../identity/identity-repository.js";
import type { SessionRepository } from "../session/session-repository.js";

export class AuthService {
  constructor(
    private readonly otp: OtpService,
    private readonly identities: IdentityRepository,
    private readonly sessions: SessionRepository
  ) {}

  async requestOtp(rawPhone: string) {
    return this.otp.request(normalizePhone(rawPhone));
  }

  async verifyOtp(rawPhone: string, code: string) {
    const phone = normalizePhone(rawPhone);
    if (!/^\d{6}$/.test(code)) throw new Error("OTP_INVALID_OR_EXPIRED");

    await this.otp.verify(phone, code);

    const now = new Date();
    const existing = await this.identities.findByPhone(phone);
    const user = existing ?? await this.identities.createVerified(phone, now);

    if (existing && !existing.phoneVerifiedAt) {
      await this.identities.markPhoneVerified(existing.id, now);
    }

    return { userId: user.id };
  }
}
