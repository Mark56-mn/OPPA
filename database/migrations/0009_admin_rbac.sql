create table if not exists public.oppa_roles (
 id uuid primary key default gen_random_uuid(),
 name text not null unique,
 description text,
 created_at timestamptz not null default now()
);
create table if not exists public.oppa_permissions (
 id uuid primary key default gen_random_uuid(),
 code text not null unique,
 description text,
 created_at timestamptz not null default now()
);
create table if not exists public.oppa_role_permissions (
 role_id uuid not null references public.oppa_roles(id) on delete cascade,
 permission_id uuid not null references public.oppa_permissions(id) on delete cascade,
 primary key(role_id,permission_id)
);
create table if not exists public.oppa_staff (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null unique references public.oppa_users(id) on delete restrict,
 status text not null default 'active' check(status in ('active','suspended','revoked')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.oppa_staff_roles (
 staff_id uuid not null references public.oppa_staff(id) on delete cascade,
 role_id uuid not null references public.oppa_roles(id) on delete restrict,
 primary key(staff_id,role_id)
);
create index if not exists oppa_staff_status_idx on public.oppa_staff(status);
alter table public.oppa_roles enable row level security;
alter table public.oppa_permissions enable row level security;
alter table public.oppa_role_permissions enable row level security;
alter table public.oppa_staff enable row level security;
alter table public.oppa_staff_roles enable row level security;
insert into public.oppa_roles(name,description) values
 ('super_admin','Highest-risk platform administration'),
 ('admin','Platform administration'),
 ('support','Customer support operations'),
 ('fraud_analyst','Fraud and risk review'),
 ('finance','Payment and wallet operations')
on conflict(name) do nothing;
insert into public.oppa_permissions(code,description) values
 ('users.read','View user records'),
 ('users.manage','Manage user status'),
 ('wallet.read','View wallet records'),
 ('payments.read','View payment records'),
 ('payments.review','Review payment risk'),
 ('support.manage','Manage support cases'),
 ('fraud.review','Review fraud/risk cases'),
 ('audit.read','Read audit events'),
 ('staff.manage','Manage staff access')
on conflict(code) do nothing;
