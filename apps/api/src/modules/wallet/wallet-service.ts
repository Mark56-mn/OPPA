import type { WalletRepository, WalletTransaction } from "./wallet-repository.js";

export class WalletService {
  constructor(private readonly wallets: WalletRepository) {}

  async getBalance(userId: string) {
    return this.wallets.getOrCreate(userId);
  }

  async getTransactions(userId: string, limit = 50, before?: string) {
    return this.wallets.listTransactions(userId, limit, before);
  }

  /**
   * Internal ledger operation. Payment/webhook modules should call this,
   * rather than exposing arbitrary balance mutation over HTTP.
   */
  async credit(userId: string, amountMinor: number, reference: string, description?: string | null): Promise<WalletTransaction> {
    return this.wallets.credit(userId, amountMinor, reference, description);
  }

  /**
   * Internal ledger operation. All debits are atomic and cannot make
   * a wallet balance negative.
   */
  async debit(userId: string, amountMinor: number, reference: string, description?: string | null): Promise<WalletTransaction> {
    return this.wallets.debit(userId, amountMinor, reference, description);
  }
}
