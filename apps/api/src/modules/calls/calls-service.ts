import type { Pool } from "pg";
import { db } from "../../db/pool.js";

/**
 * OPPA-native Calls — Stage L vertical slice.
 *
 * Architecture (per OPPA_MASTER_BUILD_SPEC §15):
 * - Server = authoritative signaling + lifecycle + history. Client = media.
 * - Media transport is WebRTC (client-to-client, DTLS-SRTP per RFC 5764);
 *   the server never terminates media and holds no media keys, so there are no
 *   provider secrets and no invented cryptosystem. Security assumptions:
 *   identity is established by authenticated signaling; SDP payloads are
 *   relayed only between verified conversation members; media confidentiality
 *   is WebRTC's DTLS-SRTP, not an OPPA cryptosystem.
 * - Africa-first: signaling is REST + polling offset protocol (no WebSocket
 *   dependency), cheap on unstable networks; clients adapt media quality and
 *   may degrade to audio-only.
 *
 * Authorization invariants:
 * - Only a current conversation member may start, answer, decline, hang up or
 *   read a call. The conversation-membership check runs inside the mutating
 *   transaction, so revocation mid-call is honored.
 * - One ringing call per conversation at a time (unique partial index).
 * - A caller with an unanswered ringing call cannot start another (ring spam
 *   control) — enforced by counting their own ringing calls.
 * - Callee "busy": answering a different call while participating in an active
 *   one marks the new invite declined/busy.
 */

const RATE_WINDOW_MS = 60_000;
const RATE_MAX_CALLS = 5;
const RING_TIMEOUT_MINUTES = 2;

/**
 * Benign-abort sentinel for call transitions: unwinds the open transaction to
 * the catch block, which rolls back and returns null (not-found / no-op) instead
 * of propagating an error. Never a real failure.
 */
const ABORT: unique symbol = Symbol("calls-transition-abort");

export interface CallRecord {
  id: string;
  conversationId: string;
  callerUserId: string;
  kind: "audio" | "video";
  status: "ringing" | "active" | "ended";
  endReason: string | null;
  startedAt: Date;
  answeredAt: Date | null;
  endedAt: Date | null;
  metadata: Record<string, unknown>;
}

export interface CallEvent {
  seq: number;
  callId: string;
  eventType: string;
  payload: Record<string, unknown>;
  createdAt: Date;
}

export interface CallsStore {
  startCall(input: {
    conversationId: string;
    callerId: string;
    kind: "audio" | "video";
    metadata?: Record<string, unknown>;
  }): Promise<{ call: CallRecord; inviteSeq: number }>;
  answerCall(conversationId: string, callId: string, userId: string): Promise<CallRecord | null>;
  declineCall(conversationId: string, callId: string, userId: string, reason: "declined" | "busy"): Promise<CallRecord | null>;
  hangUp(conversationId: string, callId: string, userId: string): Promise<CallRecord | null>;
  history(conversationId: string, userId: string, limit: number, before?: string): Promise<CallRecord[]>;
  eventsSince(conversationId: string, callId: string, userId: string, sinceSeq: number): Promise<CallEvent[]>;
  signalCall(conversationId: string, callId: string, userId: string, eventType: "answer" | "hangup" | "failed", payload?: Record<string, unknown>): Promise<number>;
  timeoutStaleRinging(now: Date): Promise<number>;
  countRecentCalls(callerId: string, since: Date): Promise<number>;
}

export class CallsService {
  constructor(private readonly store: CallsStore) {}

  async start(conversationId: string, callerId: string, kind: unknown, metadata?: unknown): Promise<{ call: CallRecord; inviteSeq: number }> {
    if (conversationId.length > 128) throw new Error("CONVERSATION_NOT_FOUND");
    if (kind !== "audio" && kind !== "video") throw new Error("CALL_KIND_INVALID");
    if (metadata !== undefined && (typeof metadata !== "object" || metadata === null || Array.isArray(metadata))) {
      throw new Error("CALL_METADATA_INVALID");
    }
    // Abuse control: ring-spam rate limit per caller (cheap count before the
    // transactional insert).
    const recent = await this.store.countRecentCalls(callerId, new Date(Date.now() - RATE_WINDOW_MS));
    if (recent >= RATE_MAX_CALLS) throw new Error("CALL_RATE_LIMITED");
    const result = await this.store.startCall({
      conversationId,
      callerId,
      kind,
      metadata: metadata === undefined ? undefined : (metadata as Record<string, unknown>)
    });
    return result;
  }

  async answer(conversationId: string, callId: string, userId: string): Promise<CallRecord> {
    const call = await this.store.answerCall(conversationId, callId, userId);
    if (!call) throw new Error("CALL_NOT_FOUND");
    return call;
  }

  async decline(conversationId: string, callId: string, userId: string, busy: boolean): Promise<CallRecord> {
    const call = await this.store.declineCall(conversationId, callId, userId, busy ? "busy" : "declined");
    if (!call) throw new Error("CALL_NOT_FOUND");
    return call;
  }

  async hangUp(conversationId: string, callId: string, userId: string): Promise<CallRecord> {
    const call = await this.store.hangUp(conversationId, callId, userId);
    if (!call) throw new Error("CALL_NOT_FOUND");
    return call;
  }

  async history(conversationId: string, userId: string, limit: number, before?: string): Promise<CallRecord[]> {
    if (conversationId.length > 128) throw new Error("CONVERSATION_NOT_FOUND");
    const capped = Number.isSafeInteger(limit) && limit > 0 && limit <= 50 ? limit : 25;
    return this.store.history(conversationId, userId, capped, before);
  }

  async poll(conversationId: string, callId: string, userId: string, sinceSeq: number): Promise<CallEvent[]> {
    if (conversationId.length > 128 || callId.length > 128) throw new Error("CALL_NOT_FOUND");
    if (!Number.isSafeInteger(sinceSeq) || sinceSeq < 0 || sinceSeq > 1_000_000) {
      throw new Error("CALL_CURSOR_INVALID");
    }
    return this.store.eventsSince(conversationId, callId, userId, sinceSeq);
  }

  /** Relays client SDP/ICE signaling payloads between verified members only. */
  async signal(
    conversationId: string,
    callId: string,
    userId: string,
    eventType: unknown,
    payload?: unknown
  ): Promise<number> {
    if (eventType !== "answer" && eventType !== "hangup" && eventType !== "failed") {
      throw new Error("CALL_SIGNAL_INVALID");
    }
    if (payload !== undefined && (typeof payload !== "object" || payload === null || Array.isArray(payload))) {
      throw new Error("CALL_PAYLOAD_INVALID");
    }
    return this.store.signalCall(conversationId, callId, userId, eventType, payload as Record<string, unknown> | undefined);
  }

  async sweepStale(): Promise<number> {
    return this.store.timeoutStaleRinging(new Date(Date.now() - RING_TIMEOUT_MINUTES * 60_000));
  }
}

/** Postgres-backed store. All mutations verify membership inside the transaction. */
export class PostgresCallsStore implements CallsStore {
  /** Optional injected pool overrides the module db (test seam, non-breaking). */
  constructor(private readonly pool?: Pool) {}

  private client() {
    if (this.pool) return this.pool;
    if (!db) throw new Error("DATABASE_URL is not configured");
    return db;
  }

  async countRecentCalls(callerId: string, since: Date): Promise<number> {
    const r = await this.client().query(
      `select count(*)::int as n from public.oppa_calls
       where caller_user_id = $1 and started_at > $2`,
      [callerId, since]
    );
    return r.rows[0]?.n ?? 0;
  }

  async startCall(input: {
    conversationId: string;
    callerId: string;
    kind: "audio" | "video";
    metadata?: Record<string, unknown>;
  }): Promise<{ call: CallRecord; inviteSeq: number }> {
    const client = this.client();
    const db = await client.connect();
    try {
      await db.query("begin");
      // Membership check inside the transaction (audited invariant).
      const member = await db.query(
        `select 1 from public.oppa_conversation_members
         where conversation_id = $1 and user_id = $2 and left_at is null for update`,
        [input.conversationId, input.callerId]
      );
      if (!member.rows[0]) throw new Error("CONVERSATION_NOT_FOUND");
      // Callers with their own unanswered ringing call must hang it up first.
      const own = await db.query(
        `select 1 from public.oppa_calls
         where caller_user_id = $1 and status = 'ringing' limit 1`,
        [input.callerId]
      );
      if (own.rows[0]) throw new Error("CALL_ALREADY_RINGING");
      const inserted = await db.query<CallRecord & { caller_user_id: string; conversation_id: string; kind: string; status: string; end_reason: string | null; started_at: Date; answered_at: Date | null; ended_at: Date | null; metadata: Record<string, unknown> }>(
        `insert into public.oppa_calls(conversation_id, caller_user_id, kind, metadata)
         values ($1, $2, $3, $4::jsonb)
         returning id, conversation_id as "conversationId", caller_user_id as "callerUserId",
                   kind, status, end_reason as "endReason", started_at as "startedAt",
                   answered_at as "answeredAt", ended_at as "endedAt", metadata`,
        [input.conversationId, input.callerId, input.kind, JSON.stringify(input.metadata ?? {})]
      );
      const call = inserted.rows[0];
      // Fan out invite events to every current member (caller included).
      const members = await db.query<{ user_id: string }>(
        `select user_id from public.oppa_conversation_members
         where conversation_id = $1 and left_at is null`,
        [input.conversationId]
      );
      let inviteSeq = 0;
      for (const m of members.rows) {
        const seqr = await db.query<{ seq: number }>(
          `insert into public.oppa_call_events(call_id, user_id, seq, event_type, payload)
           values ($1, $2, 1, 'invite', $3::jsonb)
           returning seq`,
          [call.id, m.user_id, JSON.stringify({ callId: call.id, kind: call.kind, callerUserId: call.callerUserId })]
        );
        if (m.user_id === input.callerId) inviteSeq = seqr.rows[0].seq;
      }
      await db.query("commit");
      return { call, inviteSeq };
    } catch (e) {
      await db.query("rollback").catch(() => {});
      throw e;
    } finally {
      db.release();
    }
  }

  private async transition(
    conversationId: string,
    callId: string,
    userId: string,
    fn: (db: import("pg").PoolClient, call: { id: string; status: string; caller_user_id: string }) => Promise<string | null>
  ): Promise<CallRecord | null> {
    const client = this.client();
    const db = await client.connect();
    try {
      await db.query("begin");
      const member = await db.query(
        `select 1 from public.oppa_conversation_members
         where conversation_id = $1 and user_id = $2 and left_at is null`,
        [conversationId, userId]
      );
      if (!member.rows[0]) throw ABORT; // Not a member: authorization failure surfaces as not-found.
      const lock = await db.query<{ id: string; status: string; caller_user_id: string; conversation_id: string }>(
        `select id, status, caller_user_id, conversation_id from public.oppa_calls
         where id = $1 and conversation_id = $2 for update`,
        [callId, conversationId]
      );
      if (!lock.rows[0]) throw ABORT;
      const row = lock.rows[0];
      if (row.conversation_id !== conversationId) throw ABORT;
      const reason = await fn(db, row);
      if (!reason) throw ABORT;
      // ABORT has been unwound to the catch block by now.
      const updated = await db.query<CallRecord>(
        `update public.oppa_calls set
           status = case when $2 = 'answered' then 'active' else 'ended' end,
           answered_at = case when $2 = 'answered' then now() else answered_at end,
           end_reason = case when status <> 'ended' then $2 else end_reason end,
           ended_at = case when $2 <> 'answered' then now() else ended_at end
         where id = $1
         returning id, conversation_id as "conversationId", caller_user_id as "callerUserId",
                   kind, status, end_reason as "endReason", started_at as "startedAt",
                   answered_at as "answeredAt", ended_at as "endedAt", metadata`,
        [callId, reason]
      );
      // Append the signaling event for members (offset protocol).
      const eventType = reason === "answered" ? "answer" : reason === "busy" ? "busy" : reason === "cancelled" ? "cancel" : "hangup";
      await db.query(
        `insert into public.oppa_call_events(call_id, user_id, seq, event_type)
         select $1, m.user_id,
                coalesce((select max(seq) + 1 from public.oppa_call_events e
                          where e.call_id = $1 and e.user_id = m.user_id), 1),
                $2
         from public.oppa_conversation_members m
         where m.conversation_id = (select conversation_id from public.oppa_calls where id = $1)
           and m.left_at is null
         on conflict do nothing`,
        [callId, eventType]
      );
      await db.query("commit");
      return updated.rows[0] ?? null;
    } catch (e) {
      if (e !== ABORT) {
        await db.query("rollback").catch(() => {});
        throw e;
      }
      // Benign no-op exit: release the transaction cleanly.
      await db.query("rollback").catch(() => {});
      return null;
    } finally {
      db.release();
    }
  }

  async answerCall(conversationId: string, callId: string, userId: string): Promise<CallRecord | null> {
    return this.transition(conversationId, callId, userId, async (db, call) => {
      if (call.status !== "ringing") return null; // Already active/ended: race-safe no-op.
      // Busy check: an active call the user participates in marks this busy.
      const busy = await db.query(
        `select 1 from public.oppa_calls c
         where c.status = 'active'
           and (c.caller_user_id = $2
                or exists (select 1 from public.oppa_conversation_members m2
                           where m2.conversation_id = c.conversation_id
                             and m2.user_id = $2 and m2.left_at is null))
           and c.id <> $1 limit 1`,
        [call.id, userId]
      );
      return busy.rows[0] ? "busy" : "answered";
    });
  }

  async declineCall(conversationId: string, callId: string, userId: string, reason: "declined" | "busy"): Promise<CallRecord | null> {
    return this.transition(conversationId, callId, userId, async (_db, call) => {
      if (call.status !== "ringing") return null;
      if (call.caller_user_id === userId) return "cancelled"; // Caller cancels own ring.
      return reason;
    });
  }

  async hangUp(conversationId: string, callId: string, userId: string): Promise<CallRecord | null> {
    return this.transition(conversationId, callId, userId, async (_db, call) => {
      if (call.status === "ended") return null;
      if (call.status === "ringing" && call.caller_user_id === userId) return "cancelled";
      if (call.status === "ringing") return "declined"; // Ranging callee hanging up = decline.
      return "hung_up";
    });
  }

  async history(conversationId: string, userId: string, limit: number, before?: string): Promise<CallRecord[]> {
    const r = await this.client().query<CallRecord>(
      `select c.id, c.conversation_id as "conversationId", c.caller_user_id as "callerUserId",
              c.kind, c.status, c.end_reason as "endReason", c.started_at as "startedAt",
              c.answered_at as "answeredAt", c.ended_at as "endedAt", c.metadata
       from public.oppa_calls c
       where c.conversation_id = $1
         and exists (select 1 from public.oppa_conversation_members m
                     where m.conversation_id = $1 and m.user_id = $2 and m.left_at is null)
         and ($4::text is null or c.started_at < $4::timestamptz)
       order by c.started_at desc
       limit $3`,
      [conversationId, userId, limit, before ?? null]
    );
    return r.rows;
  }

  async eventsSince(conversationId: string, callId: string, userId: string, sinceSeq: number): Promise<CallEvent[]> {
    const r = await this.client().query<CallEvent>(
      `select e.seq, e.call_id as "callId", e.event_type as "eventType",
              e.payload, e.created_at as "createdAt"
       from public.oppa_call_events e
       where e.call_id = $1 and e.user_id = $2 and e.seq > $3
         and exists (select 1 from public.oppa_conversation_members m
                     where m.conversation_id = $4 and m.user_id = $2 and m.left_at is null)
       order by e.seq asc
       limit 200`,
      [callId, userId, sinceSeq, conversationId]
    );
    return r.rows;
  }

  async signalCall(
    conversationId: string,
    callId: string,
    userId: string,
    eventType: "answer" | "hangup" | "failed",
    payload?: Record<string, unknown>
  ): Promise<number> {
    const client = this.client();
    const db = await client.connect();
    try {
      await db.query("begin");
      const member = await db.query(
        `select 1 from public.oppa_conversation_members
         where conversation_id = $1 and user_id = $2 and left_at is null`,
        [conversationId, userId]
      );
      if (!member.rows[0]) throw new Error("CALL_NOT_FOUND");
      const call = await db.query<{ id: string; status: string; conversation_id: string }>(
        `select id, status, conversation_id from public.oppa_calls where id = $1 for update`,
        [callId]
      );
      const row = call.rows[0];
      if (!row || row.conversation_id !== conversationId || row.status === "ended") {
        throw new Error("CALL_NOT_FOUND");
      }
      const inserted = await db.query<{ seq: number }>(
        `insert into public.oppa_call_events(call_id, user_id, seq, event_type, payload)
         select $1, $2,
                coalesce((select max(seq) + 1 from public.oppa_call_events e
                          where e.call_id = $1 and e.user_id = $2), 1),
                $3, $4::jsonb
         returning seq`,
        [callId, userId, eventType, JSON.stringify(payload ?? {})]
      );
      await db.query("commit");
      return inserted.rows[0].seq;
    } catch (e) {
      await db.query("rollback").catch(() => {});
      throw e;
    } finally {
      db.release();
    }
  }

  async timeoutStaleRinging(now: Date): Promise<number> {
    const r = await this.client().query(
      `update public.oppa_calls set status = 'ended', end_reason = 'timeout', ended_at = now()
       where status = 'ringing' and started_at < $1`,
      [now]
    );
    return r.rowCount ?? 0;
  }
}
