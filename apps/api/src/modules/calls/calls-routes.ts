import { Router } from "express";
import type { CallsService } from "./calls-service.js";
import { requireJsonBody } from "../../http/validate.js";

/**
 * OPPA-native calls routes. Every route requires an authenticated session
 * (mounted inside the protected router). All ownership/authorization lives in
 * the service/store transactions; routes validate shapes only.
 */
export function createCallsRouter(calls: CallsService) {
  const router = Router();

  router.post("/conversations/:conversationId/calls", requireJsonBody, async (req, res, next) => {
    try {
      const kind = req.body?.kind;
      const metadata = req.body?.metadata;
      const result = await calls.start(
        String(req.params.conversationId),
        req.auth!.userId,
        kind,
        metadata
      );
      res.status(201).json(result);
    } catch (e) {
      next(e);
    }
  });

  router.post("/conversations/:conversationId/calls/:callId/answer", async (req, res, next) => {
    try {
      const call = await calls.answer(
        String(req.params.conversationId),
        String(req.params.callId),
        req.auth!.userId
      );
      res.json(call);
    } catch (e) {
      next(e);
    }
  });

  router.post("/conversations/:conversationId/calls/:callId/decline", requireJsonBody, async (req, res, next) => {
    try {
      const busy = req.body?.busy === true;
      const call = await calls.decline(
        String(req.params.conversationId),
        String(req.params.callId),
        req.auth!.userId,
        busy
      );
      res.json(call);
    } catch (e) {
      next(e);
    }
  });

  router.post("/conversations/:conversationId/calls/:callId/hangup", async (req, res, next) => {
    try {
      const call = await calls.hangUp(
        String(req.params.conversationId),
        String(req.params.callId),
        req.auth!.userId
      );
      res.json(call);
    } catch (e) {
      next(e);
    }
  });

  router.get("/conversations/:conversationId/calls", async (req, res, next) => {
    try {
      const limit = Number(req.query.limit ?? 25);
      const before = typeof req.query.before === "string" ? req.query.before : undefined;
      res.json({
        calls: await calls.history(
          String(req.params.conversationId),
          req.auth!.userId,
          Number.isFinite(limit) ? limit : 25,
          before
        )
      });
    } catch (e) {
      next(e);
    }
  });

  // Offset-based polling endpoint: cheap, reconnect-friendly signaling pull
  // (Africa-first: no WebSocket dependency for the core call flow).
  router.get("/conversations/:conversationId/calls/:callId/events", async (req, res, next) => {
    try {
      const sinceSeq = Number(req.query.sinceSeq ?? 0);
      res.json({
        events: await calls.poll(
          String(req.params.conversationId),
          String(req.params.callId),
          req.auth!.userId,
          Number.isSafeInteger(sinceSeq) ? sinceSeq : 0
        )
      });
    } catch (e) {
      next(e);
    }
  });

  // WebRTC SDP/ICE relay between verified members (server never terminates media).
  router.post("/conversations/:conversationId/calls/:callId/signal", requireJsonBody, async (req, res, next) => {
    try {
      const seq = await calls.signal(
        String(req.params.conversationId),
        String(req.params.callId),
        req.auth!.userId,
        req.body?.type,
        req.body?.payload
      );
      res.status(201).json({ seq });
    } catch (e) {
      next(e);
    }
  });

  return router;
}
