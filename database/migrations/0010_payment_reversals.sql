alter table public.oppa_payments add column if not exists reversed_at timestamptz;
alter table public.oppa_payments add column if not exists reversal_reason text;
create table if not exists public.oppa_payment_reversals (
 id uuid primary key default gen_random_uuid(),
 payment_id uuid not null references public.oppa_payments(id) on delete restrict,
 provider text not null check(provider in ('paystack','flutterwave')),
 provider_reversal_id text,
 amount_minor bigint not null check(amount_minor > 0),
 reason text not null,
 status text not null default 'pending' check(status in ('pending','completed','failed')),
 created_at timestamptz not null default now(),
 completed_at timestamptz
);
create unique index if not exists oppa_payment_reversal_payment_uidx on public.oppa_payment_reversals(payment_id);
alter table public.oppa_payment_reversals enable row level security;