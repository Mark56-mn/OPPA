import { OtpService } from "../otp/otp-service.js";
import { normalizePhone } from "../identity/phone.js";
import type { IdentityRepository } from "../identity/identity-repository.js";
import type { SessionService } from "../session/session-service.js";
import type { DeviceService } from "../device/device-service.js";
import type { RiskService } from "../risk/risk-service.js";

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
    private readonly events?: SecurityEventRecorder,
    private readonly risk?: RiskService
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

    // Risk gate: an operator block on the login scope denies authentication
    // outright; a review decision records the anomaly but lets the login
    // proceed for operator inspection. Risk unavailability must not lock
    // everyone out, so a failing risk service is treated as observability.
    if (this.risk) {
      try {
        const decision = await this.risk.getActiveDecision(user.id, "login");
        if (decision === "block") {
          await this.risk.recordEvent({
            userId: user.id,
            category: "login_anomaly",
            signal: "login_blocked",
            score: 100,
            decision: "block",
            reasons: ["Operator login block active"],
            metadata: { deviceId }
          });
          throw new Error("ACCOUNT_UNAVAILABLE");
        }
        if (decision === "review") {
          await this.risk.recordEvent({
            userId: user.id,
            category: "login_anomaly",
            signal: "login_review",
            score: 60,
            decision: "review",
            reasons: ["Operator login review active"],
            metadata: { deviceId }
          });
        }
      } catch (e) {
        if (e instanceof Error && e.message === "ACCOUNT_UNAVAILABLE") throw e;
      }
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
