create table if not exists public.oppa_audit_events (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references public.oppa_users(id) on delete set null,
  event_type text not null,
  entity_type text not null,
  entity_id text,
  request_id text,
  ip_hash text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists oppa_audit_actor_created_idx on public.oppa_audit_events(actor_user_id,created_at desc);
create index if not exists oppa_audit_entity_idx on public.oppa_audit_events(entity_type,entity_id,created_at desc);
create index if not exists oppa_audit_request_idx on public.oppa_audit_events(request_id) where request_id is not null;
alter table public.oppa_audit_events enable row level security;

create table if not exists public.oppa_payment_risk_events (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid references public.oppa_payments(id) on delete set null,
  user_id uuid references public.oppa_users(id) on delete set null,
  risk_score smallint not null check (risk_score between 0 and 100),
  decision text not null check (decision in ('allow','review','block')),
  reasons jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists oppa_payment_risk_payment_idx on public.oppa_payment_risk_events(payment_id,created_at desc);
create index if not exists oppa_payment_risk_user_idx on public.oppa_payment_risk_events(user_id,created_at desc);
alter table public.oppa_payment_risk_events enable row level security;

alter table public.oppa_payments add column if not exists risk_score smallint;
alter table public.oppa_payments add column if not exists risk_decision text;
alter table public.oppa_payments add constraint oppa_payments_risk_score_ck check (risk_score is null or risk_score between 0 and 100);
alter table public.oppa_payments add constraint oppa_payments_risk_decision_ck check (risk_decision is null or risk_decision in ('allow','review','block'));
