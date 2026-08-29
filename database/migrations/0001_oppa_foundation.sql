create extension if not exists pgcrypto;

create table if not exists public.otp_challenges (
  id uuid primary key default gen_random_uuid(),
  phone_e164 text not null,
  otp_hash text not null,
  expires_at timestamptz not null,
  attempts integer not null default 0 check (attempts >= 0),
  consumed_at timestamptz,
  provider_message_id text,
  created_at timestamptz not null default now()
);

create index if not exists otp_challenges_phone_active_idx
  on public.otp_challenges (phone_e164, expires_at)
  where consumed_at is null;

create table if not exists public.audit_events (
  id uuid primary key default gen_random_uuid(),
  event_type text not null,
  actor_user_id uuid,
  device_id uuid,
  request_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists audit_events_created_at_idx
  on public.audit_events (created_at desc);
