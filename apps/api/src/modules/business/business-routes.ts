import { Router } from "express";
import type { PostgresBusinessRepository, BusinessRole } from "./postgres-business-repository.js";
import { requireJsonBody } from "../../http/validate.js";

export function createBusinessRouter(businesses: PostgresBusinessRepository) {
  const router = Router();

  router.post("/", requireJsonBody, async (req, res, next) => {
    try {
      const name = typeof req.body?.name === "string" ? req.body.name : "";
      const description = typeof req.body?.description === "string" ? req.body.description : null;
      if (!name.trim() || name.length > 120) {
        res.status(400).json({ error: "BUSINESS_NAME_INVALID", requestId: res.locals.requestId });
        return;
      }
      const business = await businesses.createBusiness(req.auth!.userId, name, description);
      res.status(201).json(business);
    } catch (e) { next(e); }
  });

  router.get("/", async (req, res, next) => {
    try {
      res.json({ businesses: await businesses.listForOwner(req.auth!.userId) });
    } catch (e) { next(e); }
  });

  router.get("/:businessId", async (req, res, next) => {
    try {
      const businessId = String(req.params.businessId);
      const business = await businesses.getByOwner(req.auth!.userId, businessId);
      if (!business) {
        res.status(404).json({ error: "BUSINESS_NOT_FOUND", requestId: res.locals.requestId });
        return;
      }
      res.json(business);
    } catch (e) { next(e); }
  });

  router.post("/:businessId/staff", requireJsonBody, async (req, res, next) => {
    try {
      const businessId = String(req.params.businessId);
      const userId = typeof req.body?.userId === "string" ? req.body.userId : "";
      const role = typeof req.body?.role === "string" ? req.body.role : "";
      if (!userId || userId.length > 128) {
        res.status(400).json({ error: "USER_ID_REQUIRED", requestId: res.locals.requestId });
        return;
      }
      if (!["manager", "staff"].includes(role)) {
        res.status(400).json({ error: "BUSINESS_ROLE_INVALID", requestId: res.locals.requestId });
        return;
      }
      await businesses.addStaff(businessId, req.auth!.userId, userId, role as BusinessRole);
      res.status(201).json({ ok: true });
    } catch (e) { next(e); }
  });

  router.post("/:businessId/products", requireJsonBody, async (req, res, next) => {
    try {
      const businessId = String(req.params.businessId);
      const name = typeof req.body?.name === "string" ? req.body.name : "";
      const description = typeof req.body?.description === "string" ? req.body.description : null;
      const priceMinor = req.body?.priceMinor;
      if (!name.trim() || name.length > 120) {
        res.status(400).json({ error: "BUSINESS_PRODUCT_NAME_INVALID", requestId: res.locals.requestId });
        return;
      }
      if (!Number.isSafeInteger(priceMinor) || priceMinor <= 0) {
        res.status(400).json({ error: "BUSINESS_PRODUCT_PRICE_INVALID", requestId: res.locals.requestId });
        return;
      }
      const product = await businesses.createProduct(businessId, req.auth!.userId, { name, description, priceMinor });
      res.status(201).json(product);
    } catch (e) { next(e); }
  });

  router.get("/:businessId/products", async (req, res, next) => {
    try {
      const businessId = String(req.params.businessId);
      res.json({ products: await businesses.listProducts(businessId) });
    } catch (e) { next(e); }
  });

  // Customer endpoint: creates an ordinary customer order. Staff of the
  // business are rejected server-side (self-ordering blocker).
  router.post("/:businessId/orders", requireJsonBody, async (req, res, next) => {
    try {
      const businessId = String(req.params.businessId);
      const items = req.body?.items;
      const customerOrderReference = typeof req.body?.customerOrderReference === "string"
        ? req.body.customerOrderReference : undefined;
      if (!Array.isArray(items) || items.length < 1) {
        res.status(400).json({ error: "BUSINESS_ORDER_ITEMS_INVALID", requestId: res.locals.requestId });
        return;
      }
      const order = await businesses.createOrder(businessId, req.auth!.userId, { items, customerOrderReference });
      res.status(201).json(order);
    } catch (e) { next(e); }
  });

  router.get("/:businessId/orders", async (req, res, next) => {
    try {
      const businessId = String(req.params.businessId);
      const limit = Number(req.query.limit ?? 50);
      if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new Error("BUSINESS_PAGINATION_INVALID");
      const before = typeof req.query.before === "string" && req.query.before.length <= 64 ? req.query.before : null;
      res.json({ orders: await businesses.listOrdersForBusiness(businessId, req.auth!.userId, limit, before) });
    } catch (e) { next(e); }
  });

  router.get("/orders/mine", async (req, res, next) => {
    try {
      const limit = Number(req.query.limit ?? 50);
      if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new Error("BUSINESS_PAGINATION_INVALID");
      const before = typeof req.query.before === "string" && req.query.before.length <= 64 ? req.query.before : null;
      res.json({ orders: await businesses.listOrdersForCustomer(req.auth!.userId, limit, before) });
    } catch (e) { next(e); }
  });

  // Customer pays a pending order from their OPPA wallet.
  router.post("/orders/:orderId/pay", requireJsonBody, async (req, res, next) => {
    try {
      const orderId = String(req.params.orderId);
      if (!orderId || orderId.length > 128) {
        res.status(400).json({ error: "BUSINESS_ORDER_NOT_FOUND", requestId: res.locals.requestId });
        return;
      }
      res.status(200).json(await businesses.payOrder(orderId, req.auth!.userId));
    } catch (e) { next(e); }
  });

  router.get("/:businessId/analytics", async (req, res, next) => {
    try {
      const businessId = String(req.params.businessId);
      res.json(await businesses.analytics(businessId, req.auth!.userId));
    } catch (e) { next(e); }
  });

  return router;
}
