create table if not exists public.oppa_wallet_transfers (
  id uuid primary key default gen_random_uuid(),
  reference text not null unique,
  from_user_id uuid not null references public.oppa_users(id),
  to_user_id uuid not null references public.oppa_users(id),
  amount_minor bigint not null check (amount_minor > 0),
  currency text not null default 'NGN' check (currency = 'NGN'),
  status text not null default 'completed' check (status in ('completed','reversed')),
  created_at timestamptz not null default now(),
  check (from_user_id <> to_user_id)
);

create table if not exists public.oppa_wallet_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  transfer_id uuid not null references public.oppa_wallet_transfers(id) on delete restrict,
  user_id uuid not null references public.oppa_users(id),
  entry_type text not null check (entry_type in ('debit','credit')),
  amount_minor bigint not null check (amount_minor > 0),
  created_at timestamptz not null default now()
);

create unique index if not exists oppa_wallet_ledger_transfer_user_type_uidx
  on public.oppa_wallet_ledger_entries(transfer_id, user_id, entry_type);

create index if not exists oppa_wallet_ledger_user_created_idx
  on public.oppa_wallet_ledger_entries(user_id, created_at desc);

alter table public.oppa_wallet_transfers enable row level security;
alter table public.oppa_wallet_ledger_entries enable row level security;
