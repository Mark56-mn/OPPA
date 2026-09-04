import type { NotificationCategory, NotificationPreferences } from "./postgres-notification-repository.js";

export interface PublishInput {
  eventType: string;
  userId: string;
  category: NotificationCategory;
  title: string;
  body: string;
  metadata?: Record<string, unknown>;
  dedupeKey?: string;
}

export interface ClaimedEvent {
  id: string;
  userId: string;
  eventType: string;
  payload: { category: NotificationCategory; title: string; body: string; metadata?: Record<string, unknown> };
  attempts: number;
  maxAttempts: number;
}

export interface NotificationStore {
  enqueue(input: PublishInput): Promise<{ id: string; deduplicated: boolean }>;
  claimDueEvents(limit: number, now: Date): Promise<ClaimedEvent[]>;
  deliverInApp(event: ClaimedEvent): Promise<void>;
  markFailed(eventId: string, error: string, nextAttemptAt: Date): Promise<void>;
  skip(eventId: string): Promise<void>;
  preferences(userId: string): Promise<NotificationPreferences>;
}

/** Exponential backoff with jitter-free determinism: 30s, 60s, 120s, 240s, 480s. */
export function nextBackoff(attempts: number): Date {
  const capped = Math.max(0, Math.min(attempts, 5));
  return new Date(Date.now() + 30_000 * 2 ** (capped - 1));
}

export class NotificationService {
  constructor(private readonly store: NotificationStore) {}

  /** Enqueues a durable event. Delivery is asynchronous and idempotent per dedupeKey. */
  async publish(input: PublishInput): Promise<{ id: string; deduplicated: boolean }> {
    return this.store.enqueue(input);
  }

  /**
   * Processes one batch of due events. Returns the number of events resolved
   * (delivered, skipped by preference, or exhausted to failed). Preference
   * checks are read fresh per event so changes take effect without restart.
   */
  async processBatch(limit: number): Promise<{ delivered: number; skipped: number; failed: number }> {
    const events = await this.store.claimDueEvents(limit, new Date());
    let delivered = 0, skipped = 0, failed = 0;
    for (const event of events) {
      try {
        const prefs = await this.store.preferences(event.userId);
        if (prefs[event.payload.category] === false) {
          await this.store.skip(event.id);
          skipped += 1;
          continue;
        }
        await this.store.deliverInApp(event);
        delivered += 1;
      } catch (e) {
        const message = e instanceof Error ? e.message : "DELIVERY_ERROR";
        if (event.attempts >= event.maxAttempts) {
          failed += 1;
        }
        try {
          await this.store.markFailed(event.id, message, nextBackoff(event.attempts));
        } catch {
          // A failure bookkeeping error must not crash the batch.
        }
      }
    }
    return { delivered, skipped, failed };
  }
}
