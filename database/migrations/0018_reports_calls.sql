-- Migration 0018 — abuse reports + OPPA-native call signaling (Stage L).
--
-- 1. User reports: support/abuse reporting surface for V1 (support/reporting).
--    Idempotent per (reporter, reported) pair so retries and repeat gestures
--    cannot inflate operator review queues.
--
-- 2. Calls: durable signaling store for OPPA-native calls. Signaling itself is
--    server-authoritative and polled (Africa-first: no WebSocket dependency for
--    basic call flow). Media transport (WebRTC) is client-to-client; the server
--    never terminates media, so no provider secrets exist and no proprietary
--    cryptosystem is invented. Security model documented in
--    apps/api/src/modules/calls/calls-service.ts.

-- ============ 1. Abuse reports ============

create table if not exists public.oppa_user_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_user_id uuid not null references public.oppa_users(id) on delete cascade,
  reported_user_id uuid not null references public.oppa_users(id) on delete cascade,
  reason text not null,
  status text not null default 'open' check (status in ('open', 'reviewing', 'resolved', 'dismissed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (reporter_user_id <> reported_user_id)
);

-- One live report per (reporter, reported): repeated reports refresh instead of
-- multiplying. Resolved/dismissed reports keep their history.
create unique index if not exists oppa_user_reports_pair_uniq
  on public.oppa_user_reports(reporter_user_id, reported_user_id);

create index if not exists oppa_user_reports_open_idx
  on public.oppa_user_reports(status, created_at desc);

-- ============ 2. Call signaling ============

-- Durable call record: authoritative lifecycle for every OPPA-native call.
create table if not exists public.oppa_calls (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.oppa_conversations(id) on delete cascade,
  caller_user_id uuid not null references public.oppa_users(id) on delete restrict,
  kind text not null default 'audio' check (kind in ('audio', 'video')),
  -- ringing → active → ended (terminal). missed is an ended subtype set at
  -- answer-deadline, never a separate state transition.
  status text not null default 'ringing' check (status in ('ringing', 'active', 'ended')),
  end_reason text check (end_reason in
    ('answered', 'declined', 'busy', 'timeout', 'cancelled', 'failed', 'hung_up')),
  started_at timestamptz not null default now(),
  answered_at timestamptz,
  ended_at timestamptz,
  -- Informational: offer/answer SDP is conveyed out-of-band via signaling;
  -- these are brief operator/debug annotations only, never media payloads,
  -- credentials or provider secrets.
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists oppa_calls_conversation_idx
  on public.oppa_calls(conversation_id, started_at desc);

create index if not exists oppa_calls_active_idx
  on public.oppa_calls(status)
  where status in ('ringing', 'active');

-- Per-callee delivery queue: a callee acknowledges each ringing event
-- explicitly (offset-based protocol: no delivery bookkeeping needed).
create table if not exists public.oppa_call_events (
  call_id uuid not null references public.oppa_calls(id) on delete cascade,
  user_id uuid not null references public.oppa_users(id) on delete cascade,
  seq integer not null,
  event_type text not null check (event_type in
    ('invite', 'answer', 'decline', 'busy', 'cancel', 'hangup', 'failed')),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  primary key (call_id, user_id, seq)
);

create index if not exists oppa_call_events_user_idx
  on public.oppa_call_events(user_id, call_id);

alter table public.oppa_user_reports enable row level security;
alter table public.oppa_calls enable row level security;
alter table public.oppa_call_events enable row level security;
