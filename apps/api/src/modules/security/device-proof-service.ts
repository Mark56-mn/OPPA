import { createHash, createVerify, timingSafeEqual } from "node:crypto";
import type { SecurityRepository, StepUpPurpose } from "./security-repository.js";
import type { AuthorizationContext } from "./authorization-context.js";
import { authorizationContextHash, authorizationSigningPayload } from "./authorization-context.js";

export type DeviceProof = { deviceId:string; challenge:string; signature:string; context:AuthorizationContext; };
export interface SecurityProofRepository extends SecurityRepository { getActiveDevicePublicKey(userId:string,deviceId:string):Promise<string|null>; }

export class DeviceProofService {
 constructor(private readonly security:SecurityProofRepository){}
 async verify(userId:string,purpose:StepUpPurpose,input:DeviceProof){
  if(!input.deviceId||!input.challenge||!input.signature||input.signature.length>8192)throw Error("DEVICE_PROOF_INVALID");
  const challenge=await this.security.findActiveChallenge(userId,purpose);
  if(!challenge||challenge.deviceId!==input.deviceId)throw Error("DEVICE_PROOF_INVALID");
  const suppliedHash=createHash("sha256").update(input.challenge).digest("hex");
  const expectedHash=Buffer.from(challenge.challengeHash,"utf8"), receivedHash=Buffer.from(suppliedHash,"utf8");
  if(expectedHash.length!==receivedHash.length||!timingSafeEqual(expectedHash,receivedHash)){await this.recordFailure(userId,input.deviceId,challenge.id,purpose,"challenge_invalid");throw Error("DEVICE_PROOF_INVALID");}
  const suppliedContextHash=authorizationContextHash(purpose,input.context);
  if(!challenge.contextHash||challenge.contextHash.length!==suppliedContextHash.length||!timingSafeEqual(Buffer.from(challenge.contextHash,"utf8"),Buffer.from(suppliedContextHash,"utf8"))){await this.recordFailure(userId,input.deviceId,challenge.id,purpose,"context_invalid");throw Error("DEVICE_PROOF_INVALID");}
  const publicKey=await this.security.getActiveDevicePublicKey(userId,input.deviceId);
  if(!publicKey){await this.recordFailure(userId,input.deviceId,challenge.id,purpose,"device_key_unavailable");throw Error("DEVICE_PROOF_INVALID");}
  let valid=false;
  try{const verifier=createVerify("SHA256");verifier.update(authorizationSigningPayload(input.challenge,purpose,input.context),"utf8");verifier.end();valid=verifier.verify(publicKey,Buffer.from(input.signature,"base64url"));}catch{valid=false}
  if(!valid){await this.recordFailure(userId,input.deviceId,challenge.id,purpose,"signature_invalid");throw Error("DEVICE_PROOF_INVALID");}
  if(!await this.security.consumeChallenge(challenge.id,new Date()))throw Error("DEVICE_PROOF_INVALID");
  await this.security.recordEvent({userId,deviceId:input.deviceId,eventType:"security.device_proof_verified",severity:"info",metadata:{purpose}});
  return true;
 }
 private async recordFailure(userId:string,deviceId:string,challengeId:string,purpose:StepUpPurpose,reason:string){await this.security.incrementChallengeAttempt(challengeId);await this.security.recordEvent({userId,deviceId,eventType:"security.device_proof_failed",severity:"warning",metadata:{purpose,reason}});}
}
