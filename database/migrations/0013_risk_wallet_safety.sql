-- Deterministic, explainable Risk & Abuse primitives plus wallet money-safety
-- enforcement. All statements are idempotent.

create table if not exists public.oppa_risk_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.oppa_users(id) on delete cascade,
  device_id uuid references public.oppa_devices(id) on delete set null,
  category text not null check (category in
    ('otp_abuse','registration_velocity','login_anomaly','device_anomaly',
     'transfer_velocity','payment_anomaly','repeated_failure',
     'account_takeover','merchant_risk','spam_abuse')),
  signal text not null,
  score smallint not null default 0 check (score between 0 and 100),
  decision text not null default 'allow' check (decision in ('allow','review','block')),
  reasons jsonb not null default '[]'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists oppa_risk_events_user_created_idx
  on public.oppa_risk_events(user_id, created_at desc);
create index if not exists oppa_risk_events_created_idx
  on public.oppa_risk_events(created_at desc);

-- Operator-issued review/block decisions enforced by money-movement paths.
create table if not exists public.oppa_risk_decisions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.oppa_users(id) on delete cascade,
  scope text not null check (scope in ('user','transfer','payment','otp','login')),
  decision text not null check (decision in ('allow','review','block')),
  reason text not null check (length(reason) between 1 and 500),
  expires_at timestamptz,
  created_by uuid references public.oppa_users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists oppa_risk_decisions_active_idx
  on public.oppa_risk_decisions(user_id, scope)
  where expires_at is null or expires_at > now();

-- Per-user transfer limits (minor units / NGN). Defaults apply when no row
-- exists; operators tune per user via the Control Center.
create table if not exists public.oppa_wallet_limits (
  user_id uuid primary key references public.oppa_users(id) on delete cascade,
  max_single_transfer_minor bigint not null default 100000000 check (max_single_transfer_minor > 0),
  max_daily_total_minor bigint not null default 500000000 check (max_daily_total_minor > 0),
  max_daily_count integer not null default 50 check (max_daily_count > 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.oppa_wallet_daily_counters (
  user_id uuid not null references public.oppa_users(id) on delete cascade,
  day date not null,
  total_minor bigint not null default 0 check (total_minor >= 0),
  count integer not null default 0 check (count >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, day)
);

alter table public.oppa_risk_events enable row level security;
alter table public.oppa_risk_decisions enable row level security;
alter table public.oppa_wallet_limits enable row level security;
alter table public.oppa_wallet_daily_counters enable row level security;

-- Grant the seeded fraud-analyst role the risk/permission review capability.
insert into public.oppa_role_permissions(role_id, permission_id)
select r.id, p.id
from public.oppa_roles r
cross join public.oppa_permissions p
where r.name = 'fraud_analyst' and p.code in ('fraud.review','payments.review','users.read')
on conflict do nothing;