import type {
  RiskCategory, RiskDecision, RiskDecisionRecord, RiskEventInput,
  RiskEventRecord, RiskRepository, RiskScope
} from "./risk-repository.js";

const CATEGORIES = new Set<RiskCategory>([
  "otp_abuse", "registration_velocity", "login_anomaly", "device_anomaly",
  "transfer_velocity", "payment_anomaly", "repeated_failure",
  "account_takeover", "merchant_risk", "spam_abuse"
]);
const SCOPES = new Set<RiskScope>(["user", "transfer", "payment", "otp", "login"]);
const DECISIONS = new Set<RiskDecision>(["allow", "review", "block"]);

export class RiskService {
  constructor(private readonly repo: RiskRepository) {}

  async recordEvent(input: RiskEventInput): Promise<void> {
    if (!CATEGORIES.has(input.category)) throw new Error("RISK_CATEGORY_INVALID");
    if (!input.signal || input.signal.length > 120) throw new Error("RISK_SIGNAL_INVALID");
    if (input.score !== undefined && (!Number.isInteger(input.score) || input.score < 0 || input.score > 100)) {
      throw new Error("RISK_SCORE_INVALID");
    }
    if (input.decision !== undefined && !DECISIONS.has(input.decision)) throw new Error("RISK_DECISION_INVALID");
    await this.repo.recordEvent(input);
  }

  async getActiveDecision(userId: string, scope: RiskScope): Promise<RiskDecision | null> {
    if (!SCOPES.has(scope)) throw new Error("RISK_SCOPE_INVALID");
    return this.repo.getActiveDecision(userId, scope);
  }

  listDecisions(userId: string, limit: number): Promise<RiskDecisionRecord[]> {
    return this.repo.listDecisions(userId, limit);
  }

  listRecentEvents(userId: string, limit: number): Promise<RiskEventRecord[]> {
    return this.repo.listRecentEvents(userId, limit);
  }
}