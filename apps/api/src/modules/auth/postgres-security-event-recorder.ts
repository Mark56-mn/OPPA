import { db } from "../../db/pool.js";
import type { SecurityEventRecorder } from "../auth/auth-service.js";

export class PostgresSecurityEventRecorder implements SecurityEventRecorder {
  async record(input: {
    userId: string;
    deviceId?: string;
    sessionId?: string;
    eventType: string;
    severity: "info" | "warning" | "critical";
    metadata?: Record<string, unknown>;
  }): Promise<void> {
    await db!.query(
      `insert into public.oppa_security_events(user_id, device_id, session_id, event_type, severity, metadata)
       values($1,$2,$3,$4,$5,$6::jsonb)`,
      [input.userId, input.deviceId ?? null, input.sessionId ?? null, input.eventType, input.severity, JSON.stringify(input.metadata ?? {})]
    );
  }
}
