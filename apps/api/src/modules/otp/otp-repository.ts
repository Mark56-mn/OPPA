export interface OtpChallenge {
  id: string;
  phone: string;
  otpHash: string;
  expiresAt: Date;
  attempts: number;
  consumedAt: Date | null;
  providerMessageId: string | null;
}

export interface OtpRepository {
  invalidateActive(phone: string, now: Date): Promise<void>;
  create(challenge: OtpChallenge): Promise<void>;
  getActive(phone: string, now: Date): Promise<OtpChallenge | null>;
  consume(id: string, now: Date): Promise<void>;
  incrementAttempts(id: string): Promise<number>;
}
