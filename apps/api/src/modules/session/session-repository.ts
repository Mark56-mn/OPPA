export interface SessionRecord {
  id: string;
  userId: string;
  deviceId: string;
  expiresAt: Date;
}

export interface SessionRepository {
  create(input: {
    userId: string;
    deviceId: string;
    refreshTokenHash: string;
    expiresAt: Date;
  }): Promise<SessionRecord>;
  revoke(sessionId: string, revokedAt: Date): Promise<void>;
}
