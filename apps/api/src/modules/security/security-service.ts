import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import type { SecurityRepository, StepUpPurpose } from "./security-repository.js";
const TTL_MS=5*60*1000; const MAX_ATTEMPTS=5;
const hash=(v:string)=>createHash("sha256").update(v).digest("hex");
export class SecurityService{
 constructor(private readonly security:SecurityRepository){}
 async createStepUp(userId:string,purpose:StepUpPurpose,deviceId:string){
  if(!deviceId||deviceId.length>128)throw Error("DEVICE_ID_INVALID");
  if(!await this.security.isActiveDevice(userId,deviceId))throw Error("DEVICE_NOT_ACTIVE");
  const raw=randomBytes(32).toString("base64url"); const expiresAt=new Date(Date.now()+TTL_MS);
  await this.security.createChallenge({userId,deviceId,purpose,challengeHash:hash(raw),expiresAt,maxAttempts:MAX_ATTEMPTS});
  await this.security.recordEvent({userId,deviceId,eventType:"security.step_up_created",severity:"info",metadata:{purpose}});
  return {challenge:raw,expiresAt:expiresAt.toISOString()};
 }
 async consumeStepUp(userId:string,challenge:string,purpose:StepUpPurpose){
  if(!challenge||challenge.length>128)throw Error("STEP_UP_INVALID");
  const record=await this.security.findActiveChallenge(userId,purpose); if(!record)throw Error("STEP_UP_INVALID");
  const a=Buffer.from(record.challengeHash,"utf8"), b=Buffer.from(hash(challenge),"utf8");
  if(a.length!==b.length||!timingSafeEqual(a,b)){await this.security.incrementChallengeAttempt(record.id);throw Error("STEP_UP_INVALID");}
  if(!await this.security.consumeChallenge(record.id,new Date()))throw Error("STEP_UP_INVALID");
  await this.security.recordEvent({userId,deviceId:record.deviceId,eventType:"security.step_up_consumed",severity:"info",metadata:{purpose}});
  return true;
 }
}
