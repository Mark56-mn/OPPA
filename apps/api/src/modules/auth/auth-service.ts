import { OtpService } from "../otp/otp-service.js";
import { normalizePhone } from "../identity/phone.js";
import type { IdentityRepository } from "../identity/identity-repository.js";
import type { SessionService } from "../session/session-service.js";
import type { DeviceService } from "../device/device-service.js";

type SecurityEventInput = {
  userId: string;
  deviceId?: string;
  sessionId?: string;
  eventType: string;
  severity: "info" | "warning" | "critical";
  metadata?: Record<string, unknown>;
};

export interface SecurityEventRecorder {
  record(input: SecurityEventInput): Promise<void>;
}

export class AuthService {
  constructor(
    private readonly otp: OtpService,
    private readonly identities: IdentityRepository,
    private readonly sessions: SessionService,
    private readonly devices: DeviceService,
    private readonly events?: SecurityEventRecorder
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
    if (existing && existing.status !== "active") {
      throw new Error("ACCOUNT_UNAVAILABLE");
    }

    const user = existing ?? await this.identities.createVerified(phone, now);

    if (existing && !existing.phoneVerifiedAt) {
      await this.identities.markPhoneVerified(existing.id, now);
    }

    const device = await this.devices.register(user.id, deviceId, "unknown");
    await this.recordSecurityEvent(user.id, device.id, "security.new_device_login", "info", {
      deviceId: device.id,
      returning: Boolean(existing)
    });
    return this.sessions.create(user.id, device.id);
  }

  async refresh(refreshToken: string) {
    return this.sessions.refresh(refreshToken);
  }

  /**
   * Records security events without ever letting observability break the
   * authentication flow.
   */
  private async recordSecurityEvent(
    userId: string,
    deviceId: string,
    eventType: string,
    severity: "info" | "warning" | "critical",
    metadata: Record<string, unknown>
  ) {
    try {
      await this.events?.record({ userId, deviceId, eventType, severity, metadata });
    } catch {
      // Observability must not block authentication.
    }
  }
}
