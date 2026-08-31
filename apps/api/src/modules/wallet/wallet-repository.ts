export type WalletTransactionType = "credit" | "debit";

export interface Wallet {
  userId: string;
  currency: "NGN";
  balanceMinor: number;
  updatedAt: string;
}

export interface WalletTransaction {
  id: string;
  userId: string;
  type: WalletTransactionType;
  amountMinor: number;
  balanceAfterMinor: number;
  reference: string;
  description: string | null;
  createdAt: string;
}

export interface WalletRepository {
  getOrCreate(userId: string): Promise<Wallet>;
  listTransactions(userId: string, limit: number, before?: string): Promise<WalletTransaction[]>;
  credit(userId: string, amountMinor: number, reference: string, description?: string | null): Promise<WalletTransaction>;
  debit(userId: string, amountMinor: number, reference: string, description?: string | null): Promise<WalletTransaction>;
}
