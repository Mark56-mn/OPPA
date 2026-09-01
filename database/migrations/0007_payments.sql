create table if not exists public.oppa_payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.oppa_users(id) on delete restrict,
  provider text not null check (provider in ('paystack','flutterwave')),
  reference text not null,
  provider_transaction_id text,
  amount_minor bigint not null check (amount_minor > 0),
  currency text not null default 'NGN' check (currency = 'NGN'),
  status text not null default 'pending' check (status in ('pending','paid','failed','reversed')),
  provider_status text,
  authorization_url text,
  metadata jsonb not null default '{}'::jsonb,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(provider, reference)
);
create unique index if not exists oppa_payments_provider_tx_uidx
  on public.oppa_payments(provider, provider_transaction_id)
  where provider_transaction_id is not null;
create index if not exists oppa_payments_user_created_idx
  on public.oppa_payments(user_id, created_at desc);
alter table public.oppa_payments enable row level security;
