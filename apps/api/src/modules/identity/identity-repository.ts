export interface UserIdentity {
  id: string;
  phoneE164: string;
  status: "active" | "locked" | "suspended" | "deleted";
  phoneVerifiedAt: Date | null;
}

export interface IdentityRepository {
  findByPhone(phoneE164: string): Promise<UserIdentity | null>;
  createVerified(phoneE164: string, verifiedAt: Date): Promise<UserIdentity>;
  markPhoneVerified(userId: string, verifiedAt: Date): Promise<void>;
}
