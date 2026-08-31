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
      const before = typeof req.query.before === "string" ? req.query.before : undefined;
      res.json({
        transactions: await wallets.listTransactions(
          req.auth!.userId,
          Number.isFinite(limit) ? limit : 50,
          before
        )
      });
    } catch (e) {
      next(e);
    }
  });

  return router;
}
