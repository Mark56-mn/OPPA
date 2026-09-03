import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import type { SecurityRepository, StepUpPurpose } from "./security-repository.js";
import { assertValidIntent, hashIntent, type SensitiveIntent } from "./intent-binding.js";
const TTL_MS=5*60*1000; const MAX_ATTEMPTS=5;
const hash=(v:string)=>createHash("sha256").update(v).digest("hex");
export class SecurityService{
 constructor(private readonly security:SecurityRepository){}
 async createStepUp(userId:string,purpose:StepUpPurpose,deviceId:string,intent?:SensitiveIntent){
  if(!deviceId||deviceId.length>128)throw Error("DEVICE_ID_INVALID");
  if(intent!==undefined)assertValidIntent(intent);
  if(!await this.security.isActiveDevice(userId,deviceId))throw Error("DEVICE_NOT_ACTIVE");
  const raw=randomBytes(32).toString("base64url"); const expiresAt=new Date(Date.now()+TTL_MS);
  const intentHash=intent===undefined?null:hashIntent(intent);
  await this.security.createChallenge({userId,deviceId,purpose,challengeHash:hash(raw),expiresAt,maxAttempts:MAX_ATTEMPTS,intentHash});
  await this.security.recordEvent({userId,deviceId,eventType:"security.step_up_created",severity:"info",metadata:{purpose,intentBound:intentHash!==null,intent:intent??undefined}});
  return {challenge:raw,expiresAt:expiresAt.toISOString()};
 }
 async consumeStepUp(userId:string,challenge:string,purpose:StepUpPurpose,intent?:SensitiveIntent){
  if(!challenge||challenge.length>128)throw Error("STEP_UP_INVALID");
  if(intent!==undefined)assertValidIntent(intent);
  const record=await this.security.findActiveChallenge(userId,purpose);
  if(!record){await this.security.recordEvent({userId,eventType:"security.step_up_failed",severity:"warning",metadata:{purpose,reason:"challenge_not_found"}});throw Error("STEP_UP_INVALID");}
  if(record.intentHash!==null){
   if(intent===undefined||!timingSafeEqual(Buffer.from(record.intentHash,"utf8"),Buffer.from(hashIntent(intent),"utf8"))){
    await this.security.incrementChallengeAttempt(record.id);
    await this.security.recordEvent({userId,deviceId:record.deviceId??undefined,eventType:"security.step_up_failed",severity:"warning",metadata:{purpose,reason:"intent_mismatch"}});
    throw Error("STEP_UP_INVALID");
   }
  }
  const a=Buffer.from(record.challengeHash,"utf8"), b=Buffer.from(hash(challenge),"utf8");
  if(a.length!==b.length||!timingSafeEqual(a,b)){
   await this.security.incrementChallengeAttempt(record.id);
   await this.security.recordEvent({userId,deviceId:record.deviceId??undefined,eventType:"security.step_up_failed",severity:"warning",metadata:{purpose,reason:"challenge_invalid"}});
   throw Error("STEP_UP_INVALID");
  }
  if(!await this.security.consumeChallenge(record.id,new Date()))throw Error("STEP_UP_INVALID");
  await this.security.recordEvent({userId,deviceId:record.deviceId??undefined,eventType:"security.step_up_consumed",severity:"info",metadata:{purpose}});
  return true;
 }
}