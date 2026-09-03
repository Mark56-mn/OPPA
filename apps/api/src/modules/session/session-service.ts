import { generateRefreshToken, hashRefreshToken } from "./session-crypto.js";
import { issueAccessToken } from "./access-token.js";
import type { SessionRepository } from "./session-repository.js";

const REFRESH_TTL_MS=30*24*60*60*1000;

export class SessionService{
 constructor(private readonly sessions:SessionRepository,private readonly pepper:string,private readonly accessTokenSecret:string){}
 async create(userId:string,deviceId:string){
  if(!userId||userId.length>128||!deviceId||deviceId.length>128)throw new Error("SESSION_INPUT_INVALID");
  const refreshToken=generateRefreshToken(),now=Date.now();
  const record=await this.sessions.create({userId,deviceId,refreshTokenHash:hashRefreshToken(refreshToken,this.pepper),expiresAt:new Date(now+REFRESH_TTL_MS)});
  const access=issueAccessToken(userId,record.id,this.accessTokenSecret,now);
  return {sessionId:record.id,accessToken:access.token,accessExpiresAt:access.expiresAt.toISOString(),refreshToken};
 }
 async refresh(refreshToken:string){
  if(!refreshToken||refreshToken.length>512)throw new Error("REFRESH_TOKEN_INVALID");
  const now=new Date(),current=await this.sessions.findActiveByRefreshHash(hashRefreshToken(refreshToken,this.pepper),now);
  if(!current)throw new Error("REFRESH_TOKEN_INVALID");
  const replacementToken=generateRefreshToken();
  const replacement=await this.sessions.rotate({sessionId:current.id,newRefreshTokenHash:hashRefreshToken(replacementToken,this.pepper),expiresAt:new Date(now.getTime()+REFRESH_TTL_MS),now});
  if(!replacement)throw new Error("REFRESH_TOKEN_INVALID");
  const access=issueAccessToken(replacement.userId,replacement.id,this.accessTokenSecret,now.getTime());
  return {sessionId:replacement.id,accessToken:access.token,accessExpiresAt:access.expiresAt.toISOString(),refreshToken:replacementToken};
 }
 async isActive(sessionId:string,userId:string){if(!sessionId||sessionId.length>128||!userId||userId.length>128)return false;return this.sessions.isActive(sessionId,userId,new Date());}
 async revoke(sessionId:string){if(!sessionId||sessionId.length>128)throw new Error("SESSION_ID_INVALID");await this.sessions.revoke(sessionId,new Date());}
}
