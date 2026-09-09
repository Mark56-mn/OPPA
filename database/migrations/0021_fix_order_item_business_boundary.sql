-- 0021 — Fix the cross-business order-item integrity boundary from 0019.
--
-- 0019 added a composite FK (product_id, order_id) -> products(id, business_id)
-- which can never match: it required the ORDER's id column to equal the
-- PRODUCT's business_id. On the live database that constraint rejected every
-- legitimate order-item insert (bug found by running the previously-skipped
-- real-Postgres tests). The correct declarative boundary:
--
--   * order_items gains business_id (denormalized, NOT NULL);
--   * two composite FKs pin both the product and the order to that SAME
--     business_id, making a cross-business item impossible at the storage
--     layer regardless of application logic;
--   * the broken 0019 constraint is dropped;
--   * the data pre-check aborts the migration (transactional) if any
--     historical cross-business rows exist, so nothing is silently deleted.
--
-- Idempotent; requires 0019.

begin;

do $$
declare
  broken_exists boolean;
  cross_rows bigint;
begin
  -- Abort early if the broken 0019 constraint is not present (nothing to do
  -- or a different schema state than expected).
  select exists (
    select 1 from pg_constraint
    where conname = 'oppa_business_order_items_same_business_fk'
      and conrelid = 'public.oppa_business_order_items'::regclass
  ) into broken_exists;

  if not broken_exists then
    raise notice '0021: broken 0019 constraint not present; verifying target state only';
  end if;

  -- Data pre-check: refuse to proceed if historical rows violate the target
  -- invariant (an order and its item product from different businesses).
  select count(*) into cross_rows
  from public.oppa_business_order_items oi
  join public.oppa_business_orders o on o.id = oi.order_id
  join public.oppa_business_products p on p.id = oi.product_id
  where o.business_id <> p.business_id;

  if cross_rows > 0 then
    raise exception '0021: % cross-business order item(s) exist; resolve data before migrating', cross_rows;
  end if;
end $$;

-- 1. Add the denormalized business_id column, backfilled from the order
--    (items inherit their order's business), then make it NOT NULL.
alter table public.oppa_business_order_items
  add column if not exists business_id uuid;

update public.oppa_business_order_items oi
set business_id = o.business_id
from public.oppa_business_orders o
where o.id = oi.order_id and oi.business_id is null;

alter table public.oppa_business_order_items
  alter column business_id set not null;

-- 2. Drop the impossible 0019 constraint.
alter table public.oppa_business_order_items
  drop constraint if exists oppa_business_order_items_same_business_fk;

-- 3. Supporting unique constraints so composite FKs can target them.
--    orders(id, business_id): id is already the PK, so this adds no storage
--    beyond the index needed for the FK.
create unique index if not exists oppa_business_orders_id_business_uidx
  on public.oppa_business_orders (id, business_id);

--    products(id, business_id): already created by 0019; keep if present.
create unique index if not exists oppa_business_products_id_business_uidx
  on public.oppa_business_products (id, business_id);

-- 4. Two composite FKs pinning item, product and order to one business.
--    Item cannot reference a product belonging to another business, and the
--    order itself cannot belong to another business.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'oppa_business_order_items_product_same_business_fk'
      and conrelid = 'public.oppa_business_order_items'::regclass
  ) then
    alter table public.oppa_business_order_items
      add constraint oppa_business_order_items_product_same_business_fk
      foreign key (product_id, business_id)
      references public.oppa_business_products (id, business_id)
      on delete restrict deferrable initially immediate;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'oppa_business_order_items_order_same_business_fk'
      and conrelid = 'public.oppa_business_order_items'::regclass
  ) then
    alter table public.oppa_business_order_items
      add constraint oppa_business_order_items_order_same_business_fk
      foreign key (order_id, business_id)
      references public.oppa_business_orders (id, business_id)
      on delete cascade deferrable initially immediate;
  end if;
end $$;

-- 5. Keep the child FK index for the new column (join/cleanup paths).
create index if not exists oppa_business_order_items_business_idx
  on public.oppa_business_order_items (business_id);

commit;
