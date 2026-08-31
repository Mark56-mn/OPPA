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
      if (b.clientMessageId !== undefined && typeof b.clientMessageId !== "string") {
        res.status(400).json({ error: "CLIENT_MESSAGE_ID_INVALID", requestId: res.locals.requestId });
        return;
      }
      const message = await messages.send(conversationId, req.auth!.userId, b);
      res.status(201).json(message);
    } catch (e) {
      next(e);
    }
  });

  return router;
}
