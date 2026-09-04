import { Router } from "express";
import type { NotificationService } from "./notification-service.js";
import type { PostgresNotificationRepository, NotificationCategory } from "./postgres-notification-repository.js";
import { isNotificationCategory } from "./postgres-notification-repository.js";
import { requireJsonBody } from "../../http/validate.js";
import { requirePermission } from "../admin/rbac.js";

export function createNotificationRouter(service: NotificationService, store: PostgresNotificationRepository) {
  const router = Router();

  router.get("/", async (req, res, next) => {
    try {
      const limit = Number(req.query.limit ?? 50);
      if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new Error("NOTIFICATION_PAGINATION_INVALID");
      const before = typeof req.query.before === "string" && req.query.before.length <= 64 ? req.query.before : null;
      const [notifications, unread] = await Promise.all([
        store.list(req.auth!.userId, limit, before),
        store.unreadCount(req.auth!.userId)
      ]);
      res.json({ notifications, unread });
    } catch (e) { next(e); }
  });

  router.get("/unread-count", async (req, res, next) => {
    try {
      res.json({ unread: await store.unreadCount(req.auth!.userId) });
    } catch (e) { next(e); }
  });

  // Marks one notification (or all when body omits the id) read for the caller.
  router.post("/read", requireJsonBody, async (req, res, next) => {
    try {
      const id = req.body?.notificationId;
      if (id !== undefined && (typeof id !== "string" || id.length > 128)) {
        res.status(400).json({ error: "NOTIFICATION_ID_INVALID", requestId: res.locals.requestId });
        return;
      }
      const updated = await store.markRead(req.auth!.userId, typeof id === "string" ? id : null);
      res.json({ updated });
    } catch (e) { next(e); }
  });

  router.get("/preferences", async (req, res, next) => {
    try {
      res.json({ preferences: await store.preferences(req.auth!.userId) });
    } catch (e) { next(e); }
  });

  router.put("/preferences", requireJsonBody, async (req, res, next) => {
    try {
      const category = req.body?.category;
      const enabled = req.body?.enabled;
      if (!isNotificationCategory(category)) {
        res.status(400).json({ error: "NOTIFICATION_CATEGORY_INVALID", requestId: res.locals.requestId });
        return;
      }
      if (typeof enabled !== "boolean") {
        res.status(400).json({ error: "NOTIFICATION_PREFERENCE_INVALID", requestId: res.locals.requestId });
        return;
      }
      await store.setPreference(req.auth!.userId, category as NotificationCategory, enabled);
      res.json({ ok: true });
    } catch (e) { next(e); }
  });

  // Processing endpoint for the background worker / ops trigger. Staff-gated:
  // ordinary users receive notifications, they do not drive the queue.
  router.post("/process", requireJsonBody, requirePermission("notifications.read"), async (req, res, next) => {
    try {
      const limit = Number(req.body?.limit ?? 20);
      if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new Error("NOTIFICATION_PAGINATION_INVALID");
      res.json(await service.processBatch(limit));
    } catch (e) { next(e); }
  });

  return router;
}
