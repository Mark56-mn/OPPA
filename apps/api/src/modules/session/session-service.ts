import { generateRefreshToken, hashRefreshToken } from "./session-crypto.js";
import { issueAccessToken } from "./access-token.js";
import type { SessionRepository } from "./session-repository.js";

const REFRESH_TTL_MS = 30 * 24 * 60 * 60 * 1000;

export class SessionService {
  constructor(
    private readonly sessions: SessionRepository,
    private readonly refreshPepper: string,
    private readonly accessTokenSecret: string
  ) {}

  async create(userId: string, deviceId: string) {
    const refreshToken = generateRefreshToken();
    const now = Date.now();
    const record = await this.sessions.create({
      userId,
      deviceId,
      refreshTokenHash: hashRefreshToken(refreshToken, this.refreshPepper),
      expiresAt: new Date(now + REFRESH_TTL_MS)
    });
    const access = issueAccessToken(userId, record.id, this.accessTokenSecret, now);

    return {
      sessionId: record.id,
      accessToken: access.token,
      accessExpiresAt: access.expiresAt.toISOString(),
      refreshToken
    };
  }
}
