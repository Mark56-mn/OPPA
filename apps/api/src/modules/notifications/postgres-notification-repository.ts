import { db } from "../../db/pool.js";

function requireDb() {
  if (!db) throw new Error("DATABASE_URL is not configured");
  return db;
}

export type NotificationCategory =
  | "security" | "device" | "message" | "wallet" | "payment" | "support" | "business";

export const NOTIFICATION_CATEGORIES: readonly NotificationCategory[] =
  ["security", "device", "message", "wallet", "payment", "support", "business"];

export function isNotificationCategory(value: unknown): value is NotificationCategory {
  return typeof value === "string" && (NOTIFICATION_CATEGORIES as readonly string[]).includes(value);
}

export interface NotificationRecord {
  id: string;
  userId: string;
  category: NotificationCategory;
  eventType: string;
  title: string;
  body: string;
  metadata: Record<string, unknown>;
  readAt: string | null;
  createdAt: string;
}

export interface NotificationPreferences {
  security: boolean; device: boolean; message: boolean; wallet: boolean;
  payment: boolean; support: boolean; business: boolean;
}

/**
 * Provider-agnostic notification store. Producers enqueue durable events via
 * `enqueue`; the delivery worker turns them into in-app notifications. Payloads
 * are validated at the boundary: no secrets, OTPs, tokens or raw financial data
 * may pass through — titles/bodies are capped and metadata must be small.
 */
export class PostgresNotificationRepository {
  async enqueue(input: {
    eventType: string;
    userId: string;
    category: NotificationCategory;
    title: string;
    body: string;
    metadata?: Record<string, unknown>;
    dedupeKey?: string;
  }): Promise<{ id: string; deduplicated: boolean }> {
    if (!input.eventType || input.eventType.length > 120) throw new Error("NOTIFICATION_EVENT_INVALID");
    if (!isNotificationCategory(input.category)) throw new Error("NOTIFICATION_CATEGORY_INVALID");
    if (!input.title?.trim() || input.title.length > 120) throw new Error("NOTIFICATION_PAYLOAD_INVALID");
    if (!input.body?.trim() || input.body.length > 500) throw new Error("NOTIFICATION_PAYLOAD_INVALID");
    if (input.dedupeKey !== undefined && (typeof input.dedupeKey !== "string" || input.dedupeKey.length > 200)) {
      throw new Error("NOTIFICATION_PAYLOAD_INVALID");
    }
    // Durable outbox insert. A repeated dedupe key is not an error: the event
    // simply keeps its original row and is delivered exactly once.
    const r = await requireDb().query(
      `insert into public.oppa_notification_outbox(event_type,user_id,dedupe_key,payload)
       values($1,$2,$3,$4::jsonb)
       on conflict (dedupe_key) where dedupe_key is not null do nothing
       returning id, (xmax = 0) as inserted`,
      [input.eventType, input.userId, input.dedupeKey ?? null, JSON.stringify({
        category: input.category, title: input.title, body: input.body, metadata: input.metadata ?? {}
      })]
    );
    if (r.rows[0]) return { id: r.rows[0].id, deduplicated: false };
    const existing = await requireDb().query(
      `select id from public.oppa_notification_outbox where dedupe_key=$1 limit 1`,
      [input.dedupeKey ?? null]
    );
    if (!existing.rows[0]) return { id: "", deduplicated: true };
    return { id: existing.rows[0].id, deduplicated: true };
  }

  /** Claims due pending events with SKIP LOCKED so concurrent workers never double-deliver. */
  async claimDueEvents(limit: number, now: Date): Promise<Array<{
    id: string; userId: string; eventType: string;
    payload: { category: NotificationCategory; title: string; body: string; metadata?: Record<string, unknown> };
    attempts: number; maxAttempts: number;
  }>> {
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new Error("NOTIFICATION_PAGINATION_INVALID");
    const client = await requireDb().connect();
    try {
      await client.query("begin");
      const r = await client.query(
        `update public.oppa_notification_outbox
         set status='processing', attempts=attempts+1
         where id in (
           select id from public.oppa_notification_outbox
           where status='pending' and next_attempt_at <= $2
           order by next_attempt_at
           limit $1
           for update skip locked
         )
         returning id, user_id as "userId", event_type as "eventType", payload, attempts, max_attempts as "maxAttempts"`,
        [limit, now]
      );
      await client.query("commit");
      return r.rows.map((row: any) => ({
        id: row.id, userId: row.userId, eventType: row.eventType,
        payload: { category: row.payload.category, title: row.payload.title, body: row.payload.body, metadata: row.payload.metadata ?? {} },
        attempts: Number(row.attempts), maxAttempts: Number(row.maxAttempts)
      }));
    } catch (e) {
      try { await client.query("rollback"); } catch {}
      throw e;
    } finally {
      client.release();
    }
  }

  /** Idempotent in-app delivery: the outbox row is marked delivered only if a notification exists. */
  async deliverInApp(event: {
    id: string; userId: string; eventType: string;
    payload: { category: NotificationCategory; title: string; body: string; metadata?: Record<string, unknown> };
  }): Promise<void> {
    const client = await requireDb().connect();
    try {
      await client.query("begin");
      const ins = await client.query(
        `insert into public.oppa_notifications(user_id,category,event_type,title,body,metadata)
         select $1,$2,$3,$4,$5,$6::jsonb
         where exists (select 1 from public.oppa_users where id=$1)
         returning id`,
        [event.userId, event.payload.category, event.eventType, event.payload.title, event.payload.body,
         JSON.stringify(event.payload.metadata ?? {})]
      );
      if (!ins.rows[0]) throw new Error("NOTIFICATION_USER_NOT_FOUND");
      await client.query(
        `update public.oppa_notification_outbox
         set status='delivered', delivered_at=now(), last_error=null
         where id=$1 and status='processing'`,
        [event.id]
      );
      await client.query("commit");
    } catch (e) {
      try { await client.query("rollback"); } catch {}
      throw e;
    } finally {
      client.release();
    }
  }

  /** Marks an event skipped (e.g. user preferences disable its category). */
  async skip(eventId: string): Promise<void> {
    await requireDb().query(
      `update public.oppa_notification_outbox set status='skipped' where id=$1 and status='processing'`,
      [eventId]
    );
  }

  async markFailed(eventId: string, error: string, nextAttemptAt: Date): Promise<void> {
    await requireDb().query(
      `update public.oppa_notification_outbox
       set status = case when attempts >= max_attempts then 'failed' else 'pending' end,
           last_error=$2, next_attempt_at=$3
       where id=$1`,
      [eventId, error.slice(0, 500), nextAttemptAt]
    );
  }

  async list(userId: string, limit: number, before: string | null): Promise<NotificationRecord[]> {
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new Error("NOTIFICATION_PAGINATION_INVALID");
    const r = await requireDb().query(
      `select id, user_id as "userId", category, event_type as "eventType", title, body,
              metadata, read_at as "readAt", created_at as "createdAt"
       from public.oppa_notifications
       where user_id=$1 and ($3::timestamptz is null or created_at < $3::timestamptz)
       order by created_at desc limit $2`,
      [userId, limit, before]
    );
    return r.rows;
  }

  async unreadCount(userId: string): Promise<number> {
    const r = await requireDb().query(
      `select count(*)::int as n from public.oppa_notifications where user_id=$1 and read_at is null`,
      [userId]
    );
    return Number(r.rows[0]?.n ?? 0);
  }

  async markRead(userId: string, notificationId: string | null): Promise<number> {
    if (notificationId !== null && (typeof notificationId !== "string" || notificationId.length > 128)) {
      throw new Error("NOTIFICATION_ID_INVALID");
    }
    const r = await requireDb().query(
      `update public.oppa_notifications set read_at=now()
       where user_id=$1 and read_at is null and ($2::uuid is null or id=$2::uuid)`,
      [userId, notificationId]
    );
    return r.rowCount ?? 0;
  }

  async preferences(userId: string): Promise<NotificationPreferences> {
    const r = await requireDb().query(
      `select category, enabled from public.oppa_notification_preferences where user_id=$1`,
      [userId]
    );
    const prefs: NotificationPreferences = {
      security: true, device: true, message: true, wallet: true, payment: true, support: true, business: true
    };
    for (const row of r.rows) {
      if (isNotificationCategory(row.category)) prefs[row.category as NotificationCategory] = Boolean(row.enabled);
    }
    return prefs;
  }

  async setPreference(userId: string, category: NotificationCategory, enabled: boolean): Promise<void> {
    if (!isNotificationCategory(category)) throw new Error("NOTIFICATION_CATEGORY_INVALID");
    await requireDb().query(
      `insert into public.oppa_notification_preferences(user_id,category,enabled,updated_at)
       values($1,$2,$3,now())
       on conflict (user_id,category) do update set enabled=$3, updated_at=now()`,
      [userId, category, enabled]
    );
  }

  /** Delivery-status counts for admin/observability surfaces. */
  async outboxStats(): Promise<Array<{ status: string; count: number }>> {
    const r = await requireDb().query(
      `select status, count(*)::int as count from public.oppa_notification_outbox group by status`
    );
    return r.rows;
  }
}
