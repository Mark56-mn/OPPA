import { Router } from "express";
import type { WalletRepository } from "./wallet-repository.js";
import type { WalletTransferRepository } from "./wallet-transfer-repository.js";
import type { SensitiveAuthorization, AuthorizationProof } from "../security/sensitive-authorization.js";

export function createWalletRouter(wallets: WalletRepository, transfers?: WalletTransferRepository, authorization?: SensitiveAuthorization) {
  const router = Router();

  router.get("/", async (req, res, next) => {
    try { res.json(await wallets.getOrCreate(req.auth!.userId)); } catch (e) { next(e); }
  });

  router.get("/transactions", async (req, res, next) => {
    try {
      const limit = Number(req.query.limit ?? 50);
      if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new Error("WALLET_LIMIT_INVALID");
      const before = typeof req.query.before === "string" ? req.query.before : undefined;
      if (before && before.length > 64) throw new Error("WALLET_CURSOR_INVALID");
      res.json({ transactions: await wallets.listTransactions(req.auth!.userId, limit, before) });
    } catch (e) { next(e); }
  });

  router.post("/transfer", async (req, res, next) => {
    try {
      if (!transfers) throw new Error("INTERNAL_SERVER_ERROR");
      const toUserId = typeof req.body?.toUserId === "string" ? req.body.toUserId : "";
      const amountMinor = req.body?.amountMinor;
      const reference = typeof req.body?.reference === "string" ? req.body.reference : "";
      if (!toUserId || toUserId.length > 128) throw new Error("USER_NOT_FOUND");
      if (!Number.isSafeInteger(amountMinor) || amountMinor <= 0) throw new Error("WALLET_AMOUNT_INVALID");
      if (!/^[A-Za-z0-9._:-]{1,160}$/.test(reference)) throw new Error("WALLET_REFERENCE_INVALID");

      const proof: AuthorizationProof = {
        deviceId: typeof req.body?.deviceId === "string" ? req.body.deviceId : "",
        challenge: typeof req.body?.challenge === "string" ? req.body.challenge : "",
        signature: typeof req.body?.signature === "string" ? req.body.signature : ""
      };
      if (!authorization) throw new Error("SENSITIVE_AUTH_UNAVAILABLE");
      await authorization.authorize({ userId: req.auth!.userId, operation: "wallet_transfer", proof });

      const result = await transfers.transfer({ fromUserId: req.auth!.userId, toUserId, amountMinor, reference });
      res.status(201).json(result);
    } catch (e) { next(e); }
  });

  return router;
}
