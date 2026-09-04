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
