create table if not exists public.oppa_wallets (
  user_id uuid primary key references public.oppa_users(id) on delete cascade,
  currency text not null default 'NGN' check (currency = 'NGN'),
  balance_minor bigint not null default 0 check (balance_minor >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.oppa_wallet_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.oppa_users(id) on delete cascade,
  type text not null check (type in ('credit','debit')),
  amount_minor bigint not null check (amount_minor > 0),
  balance_after_minor bigint not null check (balance_after_minor >= 0),
  reference text not null,
  description text,
  created_at timestamptz not null default now()
);

create unique index if not exists oppa_wallet_transactions_reference_uidx
  on public.oppa_wallet_transactions(reference);

create index if not exists oppa_wallet_transactions_user_created_idx
  on public.oppa_wallet_transactions(user_id, created_at desc);

create unique index if not exists otp_challenges_one_active_per_phone_uidx
  on public.otp_challenges(phone_e164)
  where consumed_at is null;

alter table public.oppa_wallets enable row level security;
alter table public.oppa_wallet_transactions enable row level security;
