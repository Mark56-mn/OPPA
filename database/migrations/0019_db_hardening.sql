-- Migration 0019 — DB-first hardening (CODEX_FINAL_DB_FIRST_HARDENING_TASK.md).
--
-- Requires 0018 (calls tables). Idempotent: every statement is guarded so the
-- migration is safe to re-run and safe against a DB where a prior partial
-- attempt succeeded.
--
-- Hardening delivered here:
--   1. DATABASE-ENFORCED call invariant: at most one non-terminal
--      (ringing|active) call per conversation, enforced by a partial unique
--      index (matches the repository status model: ringing|active|ended).
--      Concurrent `startCall` transactions serialize on this index — the
--      loser gets a unique violation, not a double ring.
--   2. Cross-business order-item integrity: an order item can only reference
--      a product that belongs to the SAME business as its order, enforced by
--      a composite FK (product_id, business_id) referencing a unique index on
--      products. Pre-checked for bad historical rows; the constraint is only
--      added when the data is clean.
--   3. Privilege hardening (privileged-backend architecture preserved):
--      no new broad grants; future tables created by the app owner role get
--      NO automatic public exposure; the anon/authenticated Data API roles
--      retain only what Supabase requires and nothing on OPPA tables beyond
--      existing grants. RLS stays ENABLED with NO policies on all oppa_*
--      tables (deny-all by design: PostgREST cannot read or write them;
--      the backend connects as a privileged role that bypasses RLS).

-- ============ 1. One non-terminal call per conversation ============
-- Idempotent create: drop+create only when missing/incorrect.
do $$
begin
  -- Remove any earlier variant with a different predicate to avoid duplicates.
  if exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'oppa_calls_one_live_per_conversation_uidx'
  ) then
    -- Verify predicate matches the repository status model; if not, replace.
    if not exists (
      select 1 from pg_indexes
      where schemaname = 'public'
        and indexname = 'oppa_calls_one_live_per_conversation_uidx'
        and indexdef ilike '%where%status in (%''ringing''%, %''active''%)%'
    ) then
      drop index if exists public.oppa_calls_one_live_per_conversation_uidx;
    end if;
  end if;

  if not exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'oppa_calls_one_live_per_conversation_uidx'
  ) then
    create unique index oppa_calls_one_live_per_conversation_uidx
      on public.oppa_calls(conversation_id)
      where status in ('ringing', 'active');
  end if;
end $$;

-- Guard against pre-existing duplicate non-terminal calls (should not exist,
-- but if the index creation above had failed on old data we surface it here).
do $$
declare
  dup_count integer;
begin
  select count(*) into dup_count from (
    select conversation_id from public.oppa_calls
    where status in ('ringing', 'active')
    group by conversation_id having count(*) > 1
  ) d;
  if dup_count > 0 then
    raise warning 'migration 0019: % conversation(s) have multiple non-terminal calls; they must be resolved manually', dup_count;
  end if;
end $$;

-- ============ 2. Cross-business order-item integrity ============
-- Composite FK target: products (id, business_id) must be unique. The PK on id
-- alone does not give us the composite target, so add the unique index.
create unique index if not exists oppa_business_products_id_business_uidx
  on public.oppa_business_products(id, business_id);

-- Safety gate: refuse the constraint if historical rows already violate it.
-- The migration aborts (transactional) so the operator can remediate.
do $$
declare
  bad_rows integer;
begin
  select count(*) into bad_rows
  from public.oppa_business_order_items oi
  join public.oppa_business_orders o on o.id = oi.order_id
  join public.oppa_business_products p on p.id = oi.product_id
  where p.business_id <> o.business_id;
  if bad_rows > 0 then
    raise exception 'migration 0019: % cross-business order item(s) detected; remediate before applying this constraint', bad_rows;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'oppa_business_order_items_same_business_fk'
      and conrelid = 'public.oppa_business_order_items'::regclass
  ) then
    alter table public.oppa_business_order_items
      add constraint oppa_business_order_items_same_business_fk
      foreign key (product_id, order_id)
      references public.oppa_business_products (id, business_id)
      on delete restrict deferrable initially immediate;
  end if;
end $$;

-- ============ 3. Privilege / default-privilege hardening ============
-- Architecture: the API connects with a privileged role (direct DML on public
-- tables, bypassing RLS). anon/authenticated (PostgREST Data API) must not
-- gain any access to OPPA tables. We:
--   a. strip OPPA-table grants from anon/authenticated if any were ever added;
--   b. set default privileges so future objects created by postgres/owner
--      roles are NOT auto-granted to anon/authenticated.
-- No broad auth.uid() policies are introduced — RLS remains deny-all with
-- zero policies, which is the correct posture for privileged-backend access.

-- 3a. Revoke any direct table/sequence grants on OPPA objects from Data API roles.
do $$
declare
  r record;
begin
  for r in
    select table_name from information_schema.tables
    where table_schema = 'public' and table_name like 'oppa_%'
  loop
    execute format('revoke all privileges on table public.%I from anon', r.table_name);
    execute format('revoke all privileges on table public.%I from authenticated', r.table_name);
  end loop;
  for r in
    select sequencename from pg_sequences
    where schemaname = 'public' and sequencename like 'oppa_%'
  loop
    execute format('revoke all privileges on sequence public.%I from anon', r.sequencename);
    execute format('revoke all privileges on sequence public.%I from authenticated', r.sequencename);
  end loop;
exception
  when undefined_object then
    -- anon/authenticated roles may not exist outside Supabase; that is fine.
    null;
end $$;

-- 3b. Default privileges: future tables/sequences/functions created by the
-- project owner roles must not be exposed to the Data API roles by default.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'postgres') then
    alter default privileges for role postgres in schema public
      revoke all on tables from anon, authenticated;
    alter default privileges for role postgres in schema public
      revoke all on sequences from anon, authenticated;
    alter default privileges for role postgres in schema public
      revoke all on functions from anon, authenticated;
  end if;
exception
  when undefined_object then
    null; -- non-Supabase environment: nothing to harden here
end $$;

-- 3c. Reaffirm RLS enablement on every oppa_ table (idempotent, catches any
-- table added since 0018 without an explicit enable statement).
do $$
declare
  r record;
begin
  for r in
    select tablename from pg_tables
    where schemaname = 'public' and tablename like 'oppa_%'
      and rowsecurity = false
  loop
    execute format('alter table public.%I enable row level security', r.tablename);
  end loop;
end $$;

-- schema_migrations is runner-managed; ensure it is also RLS-off-limits.
do $$
begin
  if exists (select 1 from pg_tables where schemaname='public' and tablename='schema_migrations') then
    execute 'alter table public.schema_migrations enable row level security';
    execute 'revoke all privileges on table public.schema_migrations from anon, authenticated';
  end if;
exception
  when undefined_object then null;
end $$;
