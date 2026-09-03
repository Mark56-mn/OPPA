export type RiskCategory =
  | "otp_abuse" | "registration_velocity" | "login_anomaly" | "device_anomaly"
  | "transfer_velocity" | "payment_anomaly" | "repeated_failure"
  | "account_takeover" | "merchant_risk" | "spam_abuse";

export type RiskDecision = "allow" | "review" | "block";
export type RiskScope = "user" | "transfer" | "payment" | "otp" | "login";

export interface RiskEventInput {
  userId?: string;
  deviceId?: string;
  category: RiskCategory;
  signal: string;
  score?: number;
  decision?: RiskDecision;
  reasons?: string[];
  metadata?: Record<string, unknown>;
}

export interface RiskDecisionRecord {
  id: string;
  userId: string;
  scope: RiskScope;
  decision: RiskDecision;
  reason: string;
  expiresAt: string | null;
  createdAt: string;
}

export interface RiskEventRecord {
  id: string;
  userId: string | null;
  category: RiskCategory;
  signal: string;
  score: number;
  decision: RiskDecision;
  reasons: string[];
  createdAt: string;
}

export interface TransferCounters {
  totalMinor: number;
  count: number;
}

export interface WalletLimits {
  maxSingleTransferMinor: number;
  maxDailyTotalMinor: number;
  maxDailyCount: number;
}

export interface RiskDecisionInput {
  userId: string;
  scope: RiskScope;
  decision: RiskDecision;
  reason: string;
  expiresAt?: Date;
  createdBy?: string;
}

export interface RiskRepository {
  recordEvent(input: RiskEventInput): Promise<void>;
  createDecision(input: RiskDecisionInput): Promise<void>;
  getActiveDecision(userId: string, scope: RiskScope): Promise<RiskDecision | null>;
  listDecisions(userId: string, limit: number): Promise<RiskDecisionRecord[]>;
  listRecentEvents(userId: string, limit: number): Promise<RiskEventRecord[]>;
  getOrCreateWalletLimits(userId: string): Promise<WalletLimits>;
  getTransferCounters(userId: string, day: Date): Promise<TransferCounters>;
  incrementTransferCounters(userId: string, day: Date, amountMinor: number): Promise<void>;
}