import { Router } from "express";
import type { WalletRepository } from "./wallet-repository.js";

export function createWalletRouter(wallets: WalletRepository) {
  const router = Router();

  router.get("/", async (req, res, next) => {
    try {
      res.json(await wallets.getOrCreate(req.auth!.userId));
    } catch (e) {
      next(e);
    }
  });

  router.get("/transactions", async (req, res, next) => {
    try {
      const limit = Number(req.query.limit ?? 50);
      if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) {
        throw new Error("WALLET_LIMIT_INVALID");
      }
      const before = typeof req.query.before === "string" ? req.query.before : undefined;
      if (before && before.length > 64) throw new Error("WALLET_CURSOR_INVALID");

      res.json({
        transactions: await wallets.listTransactions(req.auth!.userId, limit, before)
      });
    } catch (e) {
      next(e);
    }
  });

  return router;
}
