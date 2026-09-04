import { Router } from "express";
import type { MessageRepository } from "./message-repository.js";
import { requireJsonBody } from "../../http/validate.js";

export function createMessagingRouter(messages: MessageRepository) {
  const router = Router();

  router.get("/conversations/:conversationId/messages", async (req, res, next) => {
    try {
      const conversationId = String(req.params.conversationId);
      const limit = Number(req.query.limit ?? 50);
      const before = typeof req.query.before === "string" ? req.query.before : undefined;
      res.json({
        messages: await messages.list(
          conversationId,
          req.auth!.userId,
          Number.isFinite(limit) ? limit : 50,
          before
        )
      });
    } catch (e) {
      next(e);
    }
  });

  router.post("/conversations/:conversationId/messages", requireJsonBody, async (req, res, next) => {
    try {
      const conversationId = String(req.params.conversationId);
      const b = req.body ?? {};
      if (b.body !== undefined && typeof b.body !== "string") {
        res.status(400).json({ error: "MESSAGE_BODY_INVALID", requestId: res.locals.requestId });
        return;
      }
      if (b.messageType !== undefined && typeof b.messageType !== "string") {
        res.status(400).json({ error: "MESSAGE_TYPE_INVALID", requestId: res.locals.requestId });
        return;
      }
      if (b.clientMessageId !== undefined && (typeof b.clientMessageId !== "string" || b.clientMessageId.length > 128)) {
        res.status(400).json({ error: "CLIENT_MESSAGE_ID_INVALID", requestId: res.locals.requestId });
        return;
      }
      const message = await messages.send(conversationId, req.auth!.userId, b);
      res.status(201).json(message);
    } catch (e) {
      next(e);
    }
  });

  // Delivery/read: the caller marks their own receipts only.
  router.post("/conversations/:conversationId/read", requireJsonBody, async (req, res, next) => {
    try {
      const conversationId = String(req.params.conversationId);
      const upTo = typeof req.body?.upToMessageId === "string" && req.body.upToMessageId.length <= 128
        ? req.body.upToMessageId : undefined;
      const updated = await messages.markRead(conversationId, req.auth!.userId, upTo);
      res.json({ updated });
    } catch (e) { next(e); }
  });

  router.get("/messages/:messageId/receipts", async (req, res, next) => {
    try {
      const messageId = String(req.params.messageId);
      const conversationId = String(req.query.conversationId ?? "");
      if (!messageId || messageId.length > 128 || !conversationId || conversationId.length > 128) {
        res.status(400).json({ error: "MESSAGE_NOT_FOUND", requestId: res.locals.requestId });
        return;
      }
      res.json({ receipts: await messages.receipts(conversationId, messageId, req.auth!.userId) });
    } catch (e) { next(e); }
  });

  router.patch("/conversations/:conversationId/messages/:messageId", requireJsonBody, async (req, res, next) => {
    try {
      const conversationId = String(req.params.conversationId);
      const messageId = String(req.params.messageId);
      const body = req.body?.body;
      if (typeof body !== "string" || !body.trim()) {
        res.status(400).json({ error: "MESSAGE_BODY_REQUIRED", requestId: res.locals.requestId });
        return;
      }
      const edited = await messages.edit(conversationId, messageId, req.auth!.userId, body);
      if (!edited) {
        res.status(404).json({ error: "MESSAGE_NOT_FOUND", requestId: res.locals.requestId });
        return;
      }
      res.json(edited);
    } catch (e) { next(e); }
  });

  router.delete("/conversations/:conversationId/messages/:messageId", async (req, res, next) => {
    try {
      const conversationId = String(req.params.conversationId);
      const messageId = String(req.params.messageId);
      const removed = await messages.remove(conversationId, messageId, req.auth!.userId);
      if (!removed) {
        res.status(404).json({ error: "MESSAGE_NOT_FOUND", requestId: res.locals.requestId });
        return;
      }
      res.status(204).send();
    } catch (e) { next(e); }
  });

  return router;
}
