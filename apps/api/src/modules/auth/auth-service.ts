import { OtpService } from "../otp/otp-service.js";
import { normalizePhone } from "../identity/phone.js";
import type { IdentityRepository } from "../identity/identity-repository.js";
import type { SessionService } from "../session/session-service.js";
import type { DeviceService } from "../device/device-service.js";

export class AuthService {
  constructor(
    private readonly otp: OtpService,
    private readonly identities: IdentityRepository,
    private readonly sessions: SessionService,
    private readonly devices: DeviceService
  ) {}

  async requestOtp(rawPhone: string) {
    return this.otp.request(normalizePhone(rawPhone));
  }

  async verifyOtp(rawPhone: string, code: string, deviceId: string) {
    const phone = normalizePhone(rawPhone);
    if (!/^\d{6}$/.test(code)) throw new Error("OTP_INVALID_OR_EXPIRED");
    if (!deviceId || deviceId.length > 4096) throw new Error("DEVICE_ID_INVALID");

    await this.otp.verify(phone, code);
    const now = new Date();
    const existing = await this.identities.findByPhone(phone);
    const user = existing ?? await this.identities.createVerified(phone, now);

    if (existing && !existing.phoneVerifiedAt) {
      await this.identities.markPhoneVerified(existing.id, now);
    }

    const device = await this.devices.register(user.id, deviceId, "unknown");
    return this.sessions.create(user.id, device.id);
  }

  async refresh(refreshToken: string) {
    return this.sessions.refresh(refreshToken);
  }
}
