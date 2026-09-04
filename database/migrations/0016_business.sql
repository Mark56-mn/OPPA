-- Business / Merchant module (V1): businesses, staff roles, customers,
-- products, orders and payments. Money rules:
--   * consumer wallet permissions and merchant permissions stay separate;
--   * a merchant owner/staff account must not create an ordinary customer
--     order against its own business (enforced server-side and tested);
--   * order amounts use integer minor units and are server-authoritative.

create table if not exists public.oppa_businesses (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references public.oppa_users(id) on delete restrict,
  name text not null check (length(name) between 1 and 120),
  description text check (length(description) <= 1000),
  status text not null default 'active'
    check (status in ('active','suspended','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists oppa_businesses_owner_idx
  on public.oppa_businesses(owner_user_id);

create table if not exists public.oppa_business_staff (
  business_id uuid not null references public.oppa_businesses(id) on delete cascade,
  user_id uuid not null references public.oppa_users(id) on delete cascade,
  role text not null check (role in ('owner','manager','staff')),
  added_by uuid references public.oppa_users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (business_id, user_id)
);

create index if not exists oppa_business_staff_user_idx
  on public.oppa_business_staff(user_id);

create table if not exists public.oppa_business_customers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.oppa_businesses(id) on delete cascade,
  user_id uuid not null references public.oppa_users(id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now(),
  unique (business_id, user_id)
);

create index if not exists oppa_business_customers_business_idx
  on public.oppa_business_customers(business_id, created_at desc);

create table if not exists public.oppa_business_products (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.oppa_businesses(id) on delete cascade,
  name text not null check (length(name) between 1 and 120),
  description text check (length(description) <= 1000),
  price_minor bigint not null check (price_minor > 0),
  currency text not null default 'NGN' check (currency = 'NGN'),
  status text not null default 'active' check (status in ('active','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists oppa_business_products_business_idx
  on public.oppa_business_products(business_id, status, created_at desc);

create table if not exists public.oppa_business_orders (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.oppa_businesses(id) on delete restrict,
  customer_user_id uuid not null references public.oppa_users(id) on delete restrict,
  customer_order_reference text,
  amount_minor bigint not null check (amount_minor > 0),
  currency text not null default 'NGN' check (currency = 'NGN'),
  status text not null default 'pending'
    check (status in ('pending','paid','fulfilled','cancelled')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists oppa_business_orders_customer_ref_uidx
  on public.oppa_business_orders(customer_user_id, customer_order_reference)
  where customer_order_reference is not null;

create index if not exists oppa_business_orders_business_created_idx
  on public.oppa_business_orders(business_id, created_at desc);

create index if not exists oppa_business_orders_customer_created_idx
  on public.oppa_business_orders(customer_user_id, created_at desc);

create table if not exists public.oppa_business_order_items (
  order_id uuid not null references public.oppa_business_orders(id) on delete cascade,
  product_id uuid not null references public.oppa_business_products(id) on delete restrict,
  quantity integer not null check (quantity between 1 and 1000),
  unit_price_minor bigint not null check (unit_price_minor > 0),
  primary key (order_id, product_id)
);

alter table public.oppa_businesses enable row level security;
alter table public.oppa_business_staff enable row level security;
alter table public.oppa_business_customers enable row level security;
alter table public.oppa_business_products enable row level security;
alter table public.oppa_business_orders enable row level security;
alter table public.oppa_business_order_items enable row level security;
