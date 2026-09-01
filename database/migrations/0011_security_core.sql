create table if not exists public.oppa_step_up_challenges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.oppa_users(id) on delete cascade,
  device_id uuid references public.oppa_devices(id) on delete set null,
  purpose text not null check (purpose in ('wallet_transfer','payment_reversal','security_change','account_recovery')),
  challenge_hash text not null unique,
  expires_at timestamptz not null,
  attempts integer not null default 0 check (attempts >= 0),
  max_attempts integer not null default 5 check (max_attempts between 1 and 10),
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists oppa_step_up_user_active_idx
  on public.oppa_step_up_challenges(user_id, expires_at)
  where consumed_at is null;

create table if not exists public.oppa_security_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.oppa_users(id) on delete set null,
  device_id uuid references public.oppa_devices(id) on delete set null,
  session_id uuid references public.oppa_sessions(id) on delete set null,
  event_type text not null,
  severity text not null default 'info'
    check (severity in ('info','warning','critical')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists oppa_security_events_user_created_idx
  on public.oppa_security_events(user_id, created_at desc);

create index if not exists oppa_security_events_created_idx
  on public.oppa_security_events(created_at desc);

alter table public.oppa_step_up_challenges enable row level security;
alter table public.oppa_security_events enable row level security;
