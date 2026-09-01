export interface WalletTransferResult {
  transferId: string;
  reference: string;
  fromUserId: string;
  toUserId: string;
  amountMinor: number;
  currency: "NGN";
  status: "completed";
  createdAt: string;
}

export interface WalletTransferRepository {
  transfer(input: {
    fromUserId: string;
    toUserId: string;
    amountMinor: number;
    reference: string;
  }): Promise<WalletTransferResult>;
}
