-- Notifications + event delivery (V1: in-app channel; external channels are
-- provider-agnostic adapters for a later milestone).

create table if not exists public.oppa_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.oppa_users(id) on delete cascade,
  category text not null check (category in
    ('security','device','message','wallet','payment','support','business')),
  event_type text not null,
  title text not null check (length(title) between 1 and 120),
  body text not null check (length(body) between 1 and 500),
  metadata jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists oppa_notifications_user_created_idx
  on public.oppa_notifications(user_id, created_at desc);

create index if not exists oppa_notifications_user_unread_idx
  on public.oppa_notifications(user_id, created_at desc)
  where read_at is null;

create table if not exists public.oppa_notification_preferences (
  user_id uuid not null references public.oppa_users(id) on delete cascade,
  category text not null check (category in
    ('security','device','message','wallet','payment','support','business')),
  enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (user_id, category)
);

-- Durable outbox: producers enqueue events, a worker delivers them (currently
-- the in-app channel) with idempotency, retries/backoff and status tracking.
create table if not exists public.oppa_notification_outbox (
  id uuid primary key default gen_random_uuid(),
  event_type text not null,
  user_id uuid not null references public.oppa_users(id) on delete cascade,
  dedupe_key text,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending'
    check (status in ('pending','processing','delivered','failed','skipped')),
  attempts integer not null default 0 check (attempts >= 0),
  max_attempts integer not null default 5,
  next_attempt_at timestamptz not null default now(),
  last_error text,
  delivered_at timestamptz,
  created_at timestamptz not null default now()
);

create unique index if not exists oppa_notification_outbox_dedupe_uidx
  on public.oppa_notification_outbox(dedupe_key)
  where dedupe_key is not null;

create index if not exists oppa_notification_outbox_pending_idx
  on public.oppa_notification_outbox(next_attempt_at)
  where status = 'pending';

alter table public.oppa_notifications enable row level security;
alter table public.oppa_notification_preferences enable row level security;
alter table public.oppa_notification_outbox enable row level security;
