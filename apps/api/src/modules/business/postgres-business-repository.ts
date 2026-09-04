import { db } from "../../db/pool.js";

function requireDb() {
  if (!db) throw new Error("DATABASE_URL is not configured");
  return db;
}

export type BusinessRole = "owner" | "manager" | "staff";
export type OrderStatus = "pending" | "paid" | "fulfilled" | "cancelled";

export interface BusinessRecord {
  id: string; ownerUserId: string; name: string; description: string | null;
  status: string; createdAt: string; updatedAt: string;
}

export interface OrderRecord {
  id: string; businessId: string; customerUserId: string; customerOrderReference: string | null;
  amountMinor: number; currency: string; status: OrderStatus;
  metadata: Record<string, unknown>; createdAt: string; updatedAt: string;
}

/**
 * Business/Merchant repository. Money rules enforced here:
 *  - amounts are integer minor units, computed server-side from product prices;
 *  - a merchant owner/staff account must NOT create an ordinary customer order
 *    against its own business (self-ordering blocker);
 *  - order settlement credits the business owner's wallet exactly once, using
 *    the same deterministic transaction and idempotency rules as transfers.
 */
export class PostgresBusinessRepository {
  async createBusiness(ownerUserId: string, name: string, description: string | null): Promise<BusinessRecord> {
    if (!name.trim() || name.length > 120) throw new Error("BUSINESS_NAME_INVALID");
    if (description !== null && description.length > 1000) throw new Error("BUSINESS_DESCRIPTION_INVALID");
    const client = await requireDb().connect();
    try {
      await client.query("begin");
      const b = await client.query(
        `insert into public.oppa_businesses(owner_user_id,name,description)
         values($1,$2,$3)
         returning id, owner_user_id as "ownerUserId", name, description, status,
                   created_at as "createdAt", updated_at as "updatedAt"`,
        [ownerUserId, name.trim(), description]
      );
      await client.query(
        `insert into public.oppa_business_staff(business_id,user_id,role,added_by)
         values($1,$1,'owner',$1) on conflict do nothing`,
        [b.rows[0].id]
      );
      await client.query(
        `insert into public.oppa_audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)
         values($1,'business.created','business',$2,$3::jsonb)`,
        [ownerUserId, b.rows[0].id, JSON.stringify({ name })]
      );
      await client.query("commit");
      return b.rows[0];
    } catch (e) { try { await client.query("rollback"); } catch {} throw e; } finally { client.release(); }
  }

  async getByOwner(ownerUserId: string, businessId: string): Promise<BusinessRecord | null> {
    const r = await requireDb().query(
      `select id, owner_user_id as "ownerUserId", name, description, status,
              created_at as "createdAt", updated_at as "updatedAt"
       from public.oppa_businesses where id=$1 and owner_user_id=$2 limit 1`,
      [businessId, ownerUserId]
    );
    return r.rows[0] ?? null;
  }

  async listForOwner(ownerUserId: string): Promise<BusinessRecord[]> {
    const r = await requireDb().query(
      `select b.id, b.owner_user_id as "ownerUserId", b.name, b.description, b.status,
              b.created_at as "createdAt", b.updated_at as "updatedAt"
       from public.oppa_businesses b
       join public.oppa_business_staff s on s.business_id=b.id and s.user_id=$1
       where b.owner_user_id=$1 or s.user_id=$1
       order by b.created_at desc limit 100`,
      [ownerUserId]
    );
    return r.rows;
  }

  /** Role of a user in a business, or null when not staff. */
  async roleOf(businessId: string, userId: string): Promise<BusinessRole | null> {
    const r = await requireDb().query(
      `select role from public.oppa_business_staff where business_id=$1 and user_id=$2 limit 1`,
      [businessId, userId]
    );
    return (r.rows[0]?.role as BusinessRole) ?? null;
  }

  async addStaff(businessId: string, actorUserId: string, newMemberId: string, role: BusinessRole): Promise<void> {
    if (!["manager", "staff"].includes(role)) throw new Error("BUSINESS_ROLE_INVALID");
    const client = await requireDb().connect();
    try {
      await client.query("begin");
      const actorRole = await client.query(
        `select role from public.oppa_business_staff where business_id=$1 and user_id=$2 for update`,
        [businessId, actorUserId]
      );
      // Only owners can add staff, and only below their own role level.
      if (actorRole.rows[0]?.role !== "owner") throw new Error("BUSINESS_PERMISSION_DENIED");
      const exists = await client.query(`select 1 from public.oppa_users where id=$1`, [newMemberId]);
      if (!exists.rows[0]) throw new Error("USER_NOT_FOUND");
      await client.query(
        `insert into public.oppa_business_staff(business_id,user_id,role,added_by)
         values($1,$2,$3,$4) on conflict (business_id,user_id)
         do update set role=$3`,
        [businessId, newMemberId, role, actorUserId]
      );
      await client.query(
        `insert into public.oppa_audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)
         values($1,'business.staff_added','business',$2,$3::jsonb)`,
        [actorUserId, businessId, JSON.stringify({ newMemberId, role })]
      );
      await client.query("commit");
    } catch (e) { try { await client.query("rollback"); } catch {} throw e; } finally { client.release(); }
  }

  async createProduct(businessId: string, actorUserId: string, input: {
    name: string; description: string | null; priceMinor: number;
  }): Promise<Record<string, unknown>> {
    if (!input.name.trim() || input.name.length > 120) throw new Error("BUSINESS_PRODUCT_NAME_INVALID");
    if (!Number.isSafeInteger(input.priceMinor) || input.priceMinor <= 0) throw new Error("BUSINESS_PRODUCT_PRICE_INVALID");
    if (input.description !== null && input.description.length > 1000) throw new Error("BUSINESS_DESCRIPTION_INVALID");
    const role = await this.roleOf(businessId, actorUserId);
    if (!role) throw new Error("BUSINESS_PERMISSION_DENIED");
    const r = await requireDb().query(
      `insert into public.oppa_business_products(business_id,name,description,price_minor)
       values($1,$2,$3,$4)
       returning id, business_id as "businessId", name, description,
                 price_minor as "priceMinor", currency, status,
                 created_at as "createdAt", updated_at as "updatedAt"`,
      [businessId, input.name.trim(), input.description, input.priceMinor]
    );
    return r.rows[0];
  }

  async listProducts(businessId: string): Promise<Array<Record<string, unknown>>> {
    const r = await requireDb().query(
      `select id, business_id as "businessId", name, description,
              price_minor as "priceMinor", currency, status,
              created_at as "createdAt", updated_at as "updatedAt"
       from public.oppa_business_products
       where business_id=$1 and status='active'
       order by created_at desc limit 200`,
      [businessId]
    );
    return r.rows;
  }

  /**
   * Creates a customer order. The order amount is derived server-side from
   * product prices (client quantity input is validated but cannot set prices).
   * Self-ordering by the business's own staff is rejected here.
   */
  async createOrder(businessId: string, customerUserId: string, input: {
    items: Array<{ productId: string; quantity: number }>;
    customerOrderReference?: string;
  }): Promise<OrderRecord> {
    if (!Array.isArray(input.items) || input.items.length < 1 || input.items.length > 50) {
      throw new Error("BUSINESS_ORDER_ITEMS_INVALID");
    }
    for (const item of input.items) {
      if (typeof item.productId !== "string" || item.productId.length > 128 ||
          !Number.isSafeInteger(item.quantity) || item.quantity < 1 || item.quantity > 1000) {
        throw new Error("BUSINESS_ORDER_ITEMS_INVALID");
      }
    }
    if (input.customerOrderReference !== undefined &&
        (!/^[A-Za-z0-9._:-]{1,160}$/.test(input.customerOrderReference))) {
      throw new Error("BUSINESS_REFERENCE_INVALID");
    }

    const client = await requireDb().connect();
    try {
      await client.query("begin");

      // BUSINESS SAFETY BLOCKER: no owner/staff self-ordering. The staff row
      // (any role) on this business disqualifies the caller as its customer.
      const staffRole = await client.query(
        `select role from public.oppa_business_staff where business_id=$1 and user_id=$2 limit 1`,
        [businessId, customerUserId]
      );
      if (staffRole.rows[0]) throw new Error("BUSINESS_ORDER_SELF_INVALID");

      const business = await client.query(
        `select id, status from public.oppa_businesses where id=$1 for update`,
        [businessId]
      );
      if (!business.rows[0]) throw new Error("BUSINESS_NOT_FOUND");
      if (business.rows[0].status !== "active") throw new Error("BUSINESS_ORDER_STATE_INVALID");

      // Lock products and compute the amount server-side.
      const productIds = input.items.map((i) => i.productId);
      const products = await client.query(
        `select id, price_minor, status from public.oppa_business_products
         where business_id=$1 and id = any($2::uuid[]) for update`,
        [businessId, productIds]
      );
      const priceById = new Map<string, { priceMinor: number; status: string }>();
      for (const row of products.rows) {
        priceById.set(String(row.id), { priceMinor: Number(row.price_minor), status: row.status });
      }
      let amountMinor = 0;
      for (const item of input.items) {
        const product = priceById.get(item.productId);
        if (!product || product.status !== "active") throw new Error("BUSINESS_PRODUCT_NOT_FOUND");
        amountMinor += product.priceMinor * item.quantity;
      }
      if (amountMinor <= 0) throw new Error("BUSINESS_ORDER_ITEMS_INVALID");

      const order = await client.query(
        `insert into public.oppa_business_orders
         (business_id,customer_user_id,customer_order_reference,amount_minor)
         values($1,$2,$3,$4)
         returning id, business_id as "businessId", customer_user_id as "customerUserId",
                   customer_order_reference as "customerOrderReference", amount_minor as "amountMinor",
                   currency, status, metadata, created_at as "createdAt", updated_at as "updatedAt"`,
        [businessId, customerUserId, input.customerOrderReference ?? null, amountMinor]
      );
      for (const item of input.items) {
        const product = priceById.get(item.productId)!;
        await client.query(
          `insert into public.oppa_business_order_items(order_id,product_id,quantity,unit_price_minor)
           values($1,$2,$3,$4)`,
          [order.rows[0].id, item.productId, item.quantity, product.priceMinor]
        );
      }
      await client.query(
        `insert into public.oppa_business_customers(business_id,user_id)
         values($1,$2) on conflict (business_id,user_id) do nothing`,
        [businessId, customerUserId]
      );
      await client.query(
        `insert into public.oppa_audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)
         values($1,'business.order_created','order',$2,$3::jsonb)`,
        [customerUserId, order.rows[0].id, JSON.stringify({ businessId, amountMinor })]
      );
      // Durable notification for the business owner (transactional outbox).
      await client.query(
        `insert into public.oppa_notification_outbox(event_type,user_id,dedupe_key,payload)
         values('business.order_created',
                (select owner_user_id from public.oppa_businesses where id=$1),
                $2,$3::jsonb)
         on conflict (dedupe_key) where dedupe_key is not null do nothing`,
        [businessId, `business_order:${order.rows[0].id}`, JSON.stringify({
          category: "business", title: "New order", body: "A customer placed an order on your business", metadata: { orderId: order.rows[0].id }
        })]
      );
      await client.query("commit");
      return { ...order.rows[0], amountMinor: Number(order.rows[0].amountMinor) };
    } catch (e) { try { await client.query("rollback"); } catch {} throw e; } finally { client.release(); }
  }

  /** Lists orders visible to a merchant actor (owner/manager/staff of the business). */
  async listOrdersForBusiness(businessId: string, actorUserId: string, limit: number, before: string | null): Promise<OrderRecord[]> {
    const role = await this.roleOf(businessId, actorUserId);
    if (!role) throw new Error("BUSINESS_PERMISSION_DENIED");
    const r = await requireDb().query(
      `select id, business_id as "businessId", customer_user_id as "customerUserId",
              customer_order_reference as "customerOrderReference", amount_minor as "amountMinor",
              currency, status, metadata, created_at as "createdAt", updated_at as "updatedAt"
       from public.oppa_business_orders
       where business_id=$1 and ($3::timestamptz is null or created_at < $3::timestamptz)
       order by created_at desc limit $2`,
      [businessId, limit, before]
    );
    return r.rows.map((row: any) => ({ ...row, amountMinor: Number(row.amountMinor) }));
  }

  /** Lists the caller's own customer orders. */
  async listOrdersForCustomer(customerUserId: string, limit: number, before: string | null): Promise<OrderRecord[]> {
    const r = await requireDb().query(
      `select id, business_id as "businessId", customer_user_id as "customerUserId",
              customer_order_reference as "customerOrderReference", amount_minor as "amountMinor",
              currency, status, metadata, created_at as "createdAt", updated_at as "updatedAt"
       from public.oppa_business_orders
       where customer_user_id=$1 and ($3::timestamptz is null or created_at < $3::timestamptz)
       order by created_at desc limit $2`,
      [customerUserId, limit, before]
    );
    return r.rows.map((row: any) => ({ ...row, amountMinor: Number(row.amountMinor) }));
  }

  /**
   * Pays a pending order from the customer's wallet: debits the customer,
   * credits the business owner's wallet, records ledger entries and marks the
   * order paid — all atomically, idempotent per order (paid orders short-circuit).
   */
  async payOrder(orderId: string, customerUserId: string): Promise<OrderRecord> {
    const client = await requireDb().connect();
    try {
      await client.query("begin");
      const order = await client.query(
        `select id, business_id as "businessId", customer_user_id as "customerUserId",
                amount_minor as "amountMinor", currency, status
         from public.oppa_business_orders where id=$1 for update`,
        [orderId]
      );
      if (!order.rows[0]) throw new Error("BUSINESS_ORDER_NOT_FOUND");
      const o = order.rows[0];
      if (o.customerUserId !== customerUserId) throw new Error("BUSINESS_ORDER_NOT_FOUND");
      if (o.status !== "pending") throw new Error("BUSINESS_ORDER_STATE_INVALID");

      const business = await client.query(
        `select owner_user_id as "ownerUserId", status from public.oppa_businesses where id=$1 for update`,
        [o.businessId]
      );
      if (!business.rows[0] || business.rows[0].status !== "active") throw new Error("BUSINESS_ORDER_STATE_INVALID");
      const ownerUserId = String(business.rows[0].ownerUserId);

      await client.query(
        `insert into public.oppa_wallets(user_id,currency) values($1,'NGN'),($2,'NGN') on conflict (user_id) do nothing`,
        [customerUserId, ownerUserId].sort()
      );
      const ordered = [customerUserId, ownerUserId].sort();
      const locked = await client.query(
        `select user_id from public.oppa_wallets where user_id in ($1,$2) order by user_id for update`,
        [ordered[0], ordered[1]]
      );
      if (locked.rowCount !== 2) throw new Error("USER_NOT_FOUND");

      const debit = await client.query(
        `update public.oppa_wallets set balance_minor=balance_minor-$2::bigint, updated_at=now()
         where user_id=$1 and balance_minor >= $2::bigint returning balance_minor`,
        [customerUserId, o.amountMinor]
      );
      if (!debit.rows[0]) throw new Error("WALLET_INSUFFICIENT_FUNDS");
      await client.query(
        `update public.oppa_wallets set balance_minor=balance_minor+$2::bigint, updated_at=now() where user_id=$1`,
        [ownerUserId, o.amountMinor]
      );

      const reference = `order:${o.id}`;
      await client.query(
        `insert into public.oppa_wallet_transactions(user_id,type,amount_minor,balance_after_minor,reference,description)
         values($1,'debit',$2,(select balance_minor from public.oppa_wallets where user_id=$1),$3,$4)`,
        [customerUserId, o.amountMinor, reference, "Business order payment"]
      );
      await client.query(
        `insert into public.oppa_wallet_transactions(user_id,type,amount_minor,balance_after_minor,reference,description)
         values($1,'credit',$2,(select balance_minor from public.oppa_wallets where user_id=$1),$3,$4)`,
        [ownerUserId, o.amountMinor, reference, "Business order settlement"]
      );
      await client.query(
        `insert into public.oppa_wallet_ledger_entries(transfer_id,user_id,entry_type,amount_minor)
         values($1,$2,'debit',$3),($1,$4,'credit',$3)`,
        [o.id, customerUserId, o.amountMinor, ownerUserId]
      );
      const paid = await client.query(
        `update public.oppa_business_orders set status='paid', updated_at=now()
         where id=$1 and status='pending'
         returning id, business_id as "businessId", customer_user_id as "customerUserId",
                   customer_order_reference as "customerOrderReference", amount_minor as "amountMinor",
                   currency, status, metadata, created_at as "createdAt", updated_at as "updatedAt"`,
        [o.id]
      );
      if (!paid.rows[0]) throw new Error("BUSINESS_ORDER_STATE_RACE".replace("BUSINESS_ORDER_STATE_RACE", "BUSINESS_ORDER_STATE_INVALID"));
      await client.query(
        `insert into public.oppa_audit_events(actor_user_id,event_type,entity_type,entity_id,metadata)
         values($1,'business.order_paid','order',$2,$3::jsonb)`,
        [customerUserId, o.id, JSON.stringify({ businessId: o.businessId, amountMinor: Number(o.amountMinor) })]
      );
      await client.query(
        `insert into public.oppa_notification_outbox(event_type,user_id,dedupe_key,payload)
         values('business.order_paid',$1,$2,$3::jsonb),
               ('business.order_paid',(select owner_user_id from public.oppa_businesses where id=$4),$5,$6::jsonb)
         on conflict (dedupe_key) where dedupe_key is not null do nothing`,
        [customerUserId, `order_paid_customer:${o.id}`, JSON.stringify({
          category: "business", title: "Order paid", body: "Your order payment was completed", metadata: { orderId: o.id }
        }),
        o.businessId, `order_paid_owner:${o.id}`, JSON.stringify({
          category: "business", title: "Order paid", body: "A customer paid for an order", metadata: { orderId: o.id }
        })]
      );
      await client.query("commit");
      return { ...paid.rows[0], amountMinor: Number(paid.rows[0].amountMinor) };
    } catch (e) { try { await client.query("rollback"); } catch {} throw e; } finally { client.release(); }
  }

  /** Merchant analytics: order totals and counts for the owner's dashboard. */
  async analytics(businessId: string, actorUserId: string): Promise<{
    ordersTotal: number; ordersPaid: number; revenueMinor: number;
  }> {
    const role = await this.roleOf(businessId, actorUserId);
    if (!role) throw new Error("BUSINESS_PERMISSION_DENIED");
    const r = await requireDb().query(
      `select count(*)::int as orders_total,
              count(*) filter (where status in ('paid','fulfilled'))::int as orders_paid,
              coalesce(sum(amount_minor) filter (where status in ('paid','fulfilled')),0)::bigint as revenue_minor
       from public.oppa_business_orders where business_id=$1`,
      [businessId]
    );
    return {
      ordersTotal: Number(r.rows[0].orders_total),
      ordersPaid: Number(r.rows[0].orders_paid),
      revenueMinor: Number(r.rows[0].revenue_minor)
    };
  }
}
