import { generateRefreshToken, hashRefreshToken } from "./session-crypto.js";
import { issueAccessToken } from "./access-token.js";
import type { SessionRepository } from "./session-repository.js";

const ACCESS_TTL_MS = 15 * 60 * 1000;
const REFRESH_TTL_MS = 30 * 24 * 60 * 60 * 1000;

export class SessionService {
  constructor(
    private readonly sessions: SessionRepository,
    private readonly pepper: string,
    private readonly accessTokenSecret: string
  ) {}

  async create(userId: string, deviceId: string) {
    const refreshToken = generateRefreshToken();
    const now = Date.now();
    const record = await this.sessions.create({
      userId,
      deviceId,
      refreshTokenHash: hashRefreshToken(refreshToken, this.pepper),
      expiresAt: new Date(now + REFRESH_TTL_MS)
    });

    return {
      sessionId: record.id,
      accessToken: issueAccessToken(userId, record.id, this.accessTokenSecret, now).token,
      accessExpiresAt: new Date(now + ACCESS_TTL_MS).toISOString(),
      refreshToken
    };
  }

  async refresh(refreshToken: string) {
    if (!refreshToken || refreshToken.length > 512) throw new Error("REFRESH_TOKEN_INVALID");
    const now = new Date();
    const record = await this.sessions.findActiveByRefreshHash(
      hashRefreshToken(refreshToken, this.pepper),
      now
    );
    if (!record) throw new Error("REFRESH_TOKEN_INVALID");

    const access = issueAccessToken(record.userId, record.id, this.accessTokenSecret, now.getTime());
    return {
      sessionId: record.id,
      accessToken: access.token,
      accessExpiresAt: access.expiresAt.toISOString()
    };
  }

  async revoke(sessionId: string) {
    await this.sessions.revoke(sessionId, new Date());
  }
}
