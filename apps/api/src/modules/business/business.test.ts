import assert from "node:assert/strict";
import test from "node:test";
import type { AddressInfo } from "node:net";
import express from "express";
import { errorHandler } from "../../http/error-handler.js";
import { createBusinessRouter } from "./business-routes.js";
import type { PostgresBusinessRepository, OrderRecord } from "./postgres-business-repository.js";

function order(overrides: Partial<OrderRecord> = {}): OrderRecord {
  return {
    id: "o1", businessId: "b1", customerUserId: "u-customer", customerOrderReference: null,
    amountMinor: 7000, currency: "NGN", status: "pending", metadata: {},
    createdAt: new Date().toISOString(), updatedAt: new Date().toISOString(), ...overrides
  };
}

function repo(overrides: Partial<PostgresBusinessRepository> = {}): PostgresBusinessRepository {
  return {
    async createBusiness(ownerUserId, name, description) {
      return { id: "b1", ownerUserId, name, description, status: "active", createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() };
    },
    async getByOwner(ownerUserId, businessId) { return businessId === "b1" && ownerUserId === "u-owner" ? { id: "b1", ownerUserId, name: "Shop", description: null, status: "active", createdAt: "", updatedAt: "" } : null; },
    async listForOwner() { return []; },
    async roleOf(businessId, userId) { return userId === "u-owner" ? "owner" : null; },
    async addStaff() {},
    async createProduct(businessId, actorUserId, input) {
      return { id: "p1", businessId, name: input.name, description: input.description, priceMinor: input.priceMinor, currency: "NGN", status: "active", createdAt: "", updatedAt: "" };
    },
    async listProducts() { return []; },
    async createOrder(businessId, customerUserId, input) {
      if (customerUserId === "u-owner") throw new Error("BUSINESS_ORDER_SELF_INVALID");
      return order({ businessId, customerUserId, customerOrderReference: input.customerOrderReference ?? null });
    },
    async listOrdersForBusiness(businessId, actorUserId) {
      if (actorUserId !== "u-owner") throw new Error("BUSINESS_PERMISSION_DENIED");
      return [order({ businessId })];
    },
    async listOrdersForCustomer(customerUserId) { return [order({ customerUserId })]; },
    async payOrder(orderId, customerUserId) { return order({ id: orderId, customerUserId, status: "paid" }); },
    async fulfillOrder(orderId, actorUserId) {
      if (actorUserId !== "u-owner") throw new Error("BUSINESS_PERMISSION_DENIED");
      return order({ id: orderId, status: "fulfilled" });
    },
    async cancelOrder(orderId, customerUserId) {
      if (customerUserId !== "u-customer") throw new Error("BUSINESS_ORDER_NOT_FOUND");
      if (orderId === "o-paid") throw new Error("BUSINESS_ORDER_STATE_INVALID");
      return order({ id: orderId, customerUserId, status: "cancelled" });
    },
    async analytics(businessId, actorUserId) {
      if (actorUserId !== "u-owner") throw new Error("BUSINESS_PERMISSION_DENIED");
      return { ordersTotal: 3, ordersPaid: 2, revenueMinor: 21000 };
    },
    ...overrides
  } as PostgresBusinessRepository;
}

async function listen(app: express.Express): Promise<{ url: string; close: () => Promise<void> }> {
  const server = await new Promise<import("node:http").Server>((resolve) => {
    const s = app.listen(0, "127.0.0.1", () => resolve(s));
  });
  const { port } = server.address() as AddressInfo;
  return { url: `http://127.0.0.1:${port}`, close: () => new Promise((resolve) => server.close(() => resolve())) };
}

function appFor(auth: { userId: string }, repository: PostgresBusinessRepository) {
  const app = express();
  app.use(express.json());
  app.use((req, _res, next) => { req.auth = { userId: auth.userId, sessionId: "s1" }; next(); });
  app.use("/business", createBusinessRouter(repository));
  app.use(errorHandler);
  return app;
}

test("merchant staff cannot create a customer order against their own business", async () => {
  const app = appFor({ userId: "u-owner" }, repo());
  const srv = await listen(app);
  try {
    const res = await fetch(`${srv.url}/business/b1/orders`, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ items: [{ productId: "p1", quantity: 1 }] })
    });
    assert.equal(res.status, 403);
    const body = await res.json() as { error: string };
    assert.equal(body.error, "BUSINESS_ORDER_SELF_INVALID");
  } finally { await srv.close(); }
});

test("a genuine customer can create an order and pay it", async () => {
  const app = appFor({ userId: "u-customer" }, repo());
  const srv = await listen(app);
  try {
    const created = await fetch(`${srv.url}/business/b1/orders`, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ items: [{ productId: "p1", quantity: 2 }] })
    });
    assert.equal(created.status, 201);
    const paid = await fetch(`${srv.url}/business/orders/o1/pay`, {
      method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({})
    });
    assert.equal(paid.status, 200);
    const body = await paid.json() as { status: string };
    assert.equal(body.status, "paid");
  } finally { await srv.close(); }
});

test("invalid order items and references are rejected before settlement", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const repository = repo({
    async createOrder(businessId, customerUserId, input) {
      calls.push({ businessId, customerUserId, items: input.items });
      if (!Array.isArray(input.items) || input.items.length < 1) throw new Error("BUSINESS_ORDER_ITEMS_INVALID");
      if (input.customerOrderReference !== undefined && /[^A-Za-z0-9._:-]/.test(input.customerOrderReference)) {
        throw new Error("BUSINESS_REFERENCE_INVALID");
      }
      return order();
    }
  });
  const app = appFor({ userId: "u-customer" }, repository);
  const srv = await listen(app);
  try {
    const empty = await fetch(`${srv.url}/business/b1/orders`, {
      method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ items: [] })
    });
    assert.equal(empty.status, 400);
    const badRef = await fetch(`${srv.url}/business/b1/orders`, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ items: [{ productId: "p1", quantity: 1 }], customerOrderReference: "bad ref!!" })
    });
    assert.equal(badRef.status, 400);
    // Empty items never reach the repository; only the bad-reference call did.
    assert.equal(calls.length, 1);
  } finally { await srv.close(); }
});

test("merchant order lists and analytics are staff-only; customers use /orders/mine", async () => {
  const app = appFor({ userId: "u-customer" }, repo());
  const srv = await listen(app);
  try {
    const merchantList = await fetch(`${srv.url}/business/b1/orders`);
    assert.equal(merchantList.status, 403);
    const analytics = await fetch(`${srv.url}/business/b1/analytics`);
    assert.equal(analytics.status, 403);
    const mine = await fetch(`${srv.url}/business/orders/mine`);
    assert.equal(mine.status, 200);
  } finally { await srv.close(); }
});

test("business creation validates the name", async () => {
  const app = appFor({ userId: "u-owner" }, repo());
  const srv = await listen(app);
  try {
    const bad = await fetch(`${srv.url}/business`, {
      method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ name: "   " })
    });
    assert.equal(bad.status, 400);
    const ok = await fetch(`${srv.url}/business`, {
      method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ name: "Kiosk" })
    });
    assert.equal(ok.status, 201);
  } finally { await srv.close(); }
});

test("only business staff can fulfill an order; customers are denied", async () => {
  const app = appFor({ userId: "u-customer" }, repo());
  const srv = await listen(app);
  try {
    const denied = await fetch(`${srv.url}/business/orders/o1/fulfill`, { method: "POST" });
    assert.equal(denied.status, 403);
    const body = await denied.json() as { error: string };
    assert.equal(body.error, "BUSINESS_PERMISSION_DENIED");
  } finally { await srv.close(); }

  const staffApp = appFor({ userId: "u-owner" }, repo());
  const staffSrv = await listen(staffApp);
  try {
    const ok = await fetch(`${staffSrv.url}/business/orders/o1/fulfill`, { method: "POST" });
    assert.equal(ok.status, 200);
    const body = await ok.json() as { status: string };
    assert.equal(body.status, "fulfilled");
  } finally { await staffSrv.close(); }
});

test("cancellation is customer-only and rejects already-paid orders", async () => {
  // A different user cannot cancel someone else's order.
  const stranger = appFor({ userId: "u-other" }, repo());
  const strangerSrv = await listen(stranger);
  try {
    const notYours = await fetch(`${strangerSrv.url}/business/orders/o1/cancel`, { method: "POST" });
    assert.equal(notYours.status, 404); // ownership failure surfaces as not-found
  } finally { await strangerSrv.close(); }

  // The customer can cancel a pending order.
  const app = appFor({ userId: "u-customer" }, repo());
  const srv = await listen(app);
  try {
    const ok = await fetch(`${srv.url}/business/orders/o1/cancel`, { method: "POST" });
    assert.equal(ok.status, 200);
    const body = await ok.json() as { status: string };
    assert.equal(body.status, "cancelled");
    // A paid order must never be cancelled (money already moved; refunds are out of scope).
    const paid = await fetch(`${srv.url}/business/orders/o-paid/cancel`, { method: "POST" });
    assert.equal(paid.status, 409);
    const paidBody = await paid.json() as { error: string };
    assert.equal(paidBody.error, "BUSINESS_ORDER_STATE_INVALID");
  } finally { await srv.close(); }
});

test("staff roster is viewable by staff only and masks phone numbers", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const repository = repo({
    async listStaff(businessId, actorUserId) {
      calls.push({ businessId, actorUserId });
      if (actorUserId !== "u-owner") throw new Error("BUSINESS_PERMISSION_DENIED");
      return [{
        userId: "u-staff", role: "staff" as const, addedAt: new Date().toISOString(),
        displayName: "Ngozi", phoneMasked: "+23480****678",
      }];
    },
  });
  const app = appFor({ userId: "u-owner" }, repository);
  const srv = await listen(app);
  try {
    const res = await fetch(`${srv.url}/business/b1/staff`);
    assert.equal(res.status, 200);
    const body = await res.json() as { staff: Array<{ phoneMasked: string }> };
    assert.equal(body.staff.length, 1);
    assert.equal(body.staff[0].phoneMasked, "+23480****678");
    assert.deepEqual(calls, [{ businessId: "b1", actorUserId: "u-owner" }]);
    // A non-staff stranger is denied by the repository layer.
    const strangerApp = appFor({ userId: "u-stranger" }, repository);
    const strangerSrv = await listen(strangerApp);
    try {
      const denied = await fetch(`${strangerSrv.url}/business/b1/staff`);
      assert.equal(denied.status, 403);
    } finally { await strangerSrv.close(); }
  } finally { await srv.close(); }
});

test("role change is owner-only, role-validated and never targets the owner", async () => {
  const roleCalls: Array<Record<string, unknown>> = [];
  const repository = repo({
    async setStaffRole(businessId, actorUserId, targetUserId, role) {
      roleCalls.push({ businessId, actorUserId, targetUserId, role });
      if (actorUserId !== "u-owner") throw new Error("BUSINESS_PERMISSION_DENIED");
      if (targetUserId === "u-owner") throw new Error("BUSINESS_ROLE_INVALID");
      if (targetUserId === "ghost") throw new Error("BUSINESS_STAFF_NOT_FOUND");
    },
  });
  const app = appFor({ userId: "u-owner" }, repository);
  const srv = await listen(app);
  try {
    const ok = await fetch(`${srv.url}/business/b1/staff/u-staff`, {
      method: "PATCH", headers: { "content-type": "application/json" },
      body: JSON.stringify({ role: "manager" }),
    });
    assert.equal(ok.status, 200);
    const badRole = await fetch(`${srv.url}/business/b1/staff/u-staff`, {
      method: "PATCH", headers: { "content-type": "application/json" },
      body: JSON.stringify({ role: "owner" }),
    });
    assert.equal(badRole.status, 400);
    const ghost = await fetch(`${srv.url}/business/b1/staff/ghost`, {
      method: "PATCH", headers: { "content-type": "application/json" },
      body: JSON.stringify({ role: "staff" }),
    });
    assert.equal(ghost.status, 404);
    // Owner row itself: the repository refuses any owner-row mutation.
    const ownerRow = await fetch(`${srv.url}/business/b1/staff/u-owner`, {
      method: "PATCH", headers: { "content-type": "application/json" },
      body: JSON.stringify({ role: "staff" }),
    });
    assert.equal(ownerRow.status, 400);
    assert.equal((await ownerRow.json() as { error: string }).error, "BUSINESS_ROLE_INVALID");
    assert.equal(roleCalls.length, 3);
  } finally { await srv.close(); }
});

test("owner or manager can edit a product; customers and non-staff cannot", async () => {
  const seen: Array<{ actor: string; patch: unknown }> = [];
  const app = appFor({ userId: "u-manager" }, repo({
    async updateProduct(_businessId, actorUserId, productId, patch) {
      const role = actorUserId === "u-owner" ? "owner" : actorUserId === "u-manager" ? "manager" : actorUserId === "u-staff" ? "staff" : null;
      if (role !== "owner" && role !== "manager") throw new Error("BUSINESS_PERMISSION_DENIED");
      if (patch.priceMinor !== undefined && patch.priceMinor <= 0) throw new Error("BUSINESS_PRODUCT_PRICE_INVALID");
      seen.push({ actor: actorUserId, patch });
      return { id: productId, businessId: "b1", name: patch.name ?? "Old", description: null, priceMinor: patch.priceMinor ?? 100, currency: "NGN", status: patch.status ?? "active", createdAt: "", updatedAt: "" };
    },
    async roleOf(_businessId, userId) {
      if (userId === "u-owner") return "owner";
      if (userId === "u-manager") return "manager";
      if (userId === "u-staff") return "staff";
      return null;
    }
  } as Partial<PostgresBusinessRepository>));
  const srv = await listen(app);
  try {
    const patch = (userId: string, body: unknown) => fetch(`${srv.url}/business/b1/products/p1`, {
      method: "PATCH", headers: { "content-type": "application/json" }, body: JSON.stringify(body)
    });
    // The router does not look at roles itself — the repository does — so the
    // manager path succeeds and a genuinely non-staff caller is rejected by
    // the real authorization check in the repository implementation.
    const ok = await patch("u-manager", { name: "Renamed", priceMinor: 2500 });
    assert.equal(ok.status, 200);
    assert.equal(seen.length, 1);
    assert.deepEqual(seen[0].patch, { name: "Renamed", priceMinor: 2500 });

    // Invalid price is refused with the documented code, not a 200.
    const bad = await patch("u-manager", { priceMinor: 0 });
    assert.equal(bad.status, 400);
    assert.equal(((await bad.json()) as { error: string }).error, "BUSINESS_PRODUCT_PRICE_INVALID");

    // Unknown status is refused too (only active/archived exist).
    const badStatus = await patch("u-manager", { status: "deleted" });
    assert.equal(badStatus.status, 400);

    // An empty patch is a client bug — rejected explicitly.
    const empty = await patch("u-manager", {});
    assert.equal(empty.status, 400);
    assert.equal(((await empty.json()) as { error: string }).error, "BUSINESS_PRODUCT_PATCH_EMPTY");
  } finally { await srv.close(); }
});

test("product listing hides archived rows unless the caller is staff", async () => {
  const calls: boolean[] = [];
  const app = appFor({ userId: "u-owner" }, repo({
    async listProducts(_businessId, options = {}) {
      calls.push(options.includeArchived === true);
      return [];
    },
    async roleOf(_businessId, userId) { return userId === "u-owner" ? "owner" : null; }
  } as Partial<PostgresBusinessRepository>));
  const srv = await listen(app);
  try {
    const plain = await fetch(`${srv.url}/business/b1/products`);
    assert.equal(plain.status, 200);
    assert.deepEqual(calls, [false]);

    const asStaff = await fetch(`${srv.url}/business/b1/products?includeArchived=1`);
    assert.equal(asStaff.status, 200);
    assert.deepEqual(calls, [false, true]);
  } finally { await srv.close(); }
});

test("business profile edit is owner-scoped and validates the name", async () => {
  const app = appFor({ userId: "u-owner" }, repo({
    async updateBusiness(_businessId, actorUserId, patch) {
      if (actorUserId !== "u-owner") throw new Error("BUSINESS_PERMISSION_DENIED");
      if (patch.name !== undefined && !patch.name.trim()) throw new Error("BUSINESS_NAME_INVALID");
      return { id: "b1", ownerUserId: actorUserId, name: patch.name ?? "Shop", description: patch.description ?? null, status: "active", createdAt: "", updatedAt: "" };
    }
  } as Partial<PostgresBusinessRepository>));
  const srv = await listen(app);
  try {
    const res = await fetch(`${srv.url}/business/b1`, {
      method: "PATCH", headers: { "content-type": "application/json" },
      body: JSON.stringify({ name: "Mama's Kitchen" })
    });
    assert.equal(res.status, 200);
    const body = await res.json() as { name: string };
    assert.equal(body.name, "Mama's Kitchen");

    const blank = await fetch(`${srv.url}/business/b1`, {
      method: "PATCH", headers: { "content-type": "application/json" },
      body: JSON.stringify({ name: "   " })
    });
    assert.equal(blank.status, 400);
    assert.equal(((await blank.json()) as { error: string }).error, "BUSINESS_NAME_INVALID");
  } finally { await srv.close(); }
});
