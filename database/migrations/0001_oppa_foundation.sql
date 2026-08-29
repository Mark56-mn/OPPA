create extension if not exists pgcrypto;

create table if not exists public.oppa_users (
  id uuid primary key default gen_random_uuid(),
  phone_e164 text not null unique,
  phone_verified_at timestamptz,
  status text not null default 'active'
    check (status in ('active', 'locked', 'suspended', 'deleted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.oppa_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.oppa_users(id) on delete cascade,
  device_public_key text not null,
  platform text not null check (platform in ('android', 'ios', 'web', 'unknown')),
  status text not null default 'active'
    check (status in ('active', 'revoked')),
  registered_at timestamptz not null default now(),
  last_seen_at timestamptz
);

create index if not exists oppa_devices_user_idx
  on public.oppa_devices (user_id, status);

create table if not exists public.oppa_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.oppa_users(id) on delete cascade,
  device_id uuid not null references public.oppa_devices(id) on delete cascade,
  refresh_token_hash text not null unique,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz
);

create index if not exists oppa_sessions_user_active_idx
  on public.oppa_sessions (user_id, expires_at)
  where revoked_at is null;

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
  actor_user_id uuid references public.oppa_users(id) on delete set null,
  device_id uuid references public.oppa_devices(id) on delete set null,
  request_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists audit_events_created_at_idx
  on public.audit_events (created_at desc);

alter table public.oppa_users enable row level security;
alter table public.oppa_devices enable row level security;
alter table public.oppa_sessions enable row level security;
alter table public.otp_challenges enable row level security;
alter table public.audit_events enable row level security;
