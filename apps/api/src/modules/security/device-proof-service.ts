import { createHash, createVerify, timingSafeEqual } from "node:crypto";
import type { SecurityRepository, StepUpPurpose } from "./security-repository.js";
import { assertValidIntent, canonicalizeIntent, hashIntent, type SensitiveIntent } from "./intent-binding.js";

export type DeviceProof = {
 deviceId:string;
 challenge:string;
 signature:string;
};

export interface SecurityProofRepository extends SecurityRepository {
 getActiveDevicePublicKey(userId:string,deviceId:string):Promise<string|null>;
}

export class DeviceProofService {
 constructor(private readonly security:SecurityProofRepository){}
 async verify(userId:string,purpose:StepUpPurpose,input:DeviceProof,intent?:SensitiveIntent){
  if(!input.deviceId||!input.challenge||!input.signature||input.signature.length>8192)throw Error("DEVICE_PROOF_INVALID");
  if(intent!==undefined)assertValidIntent(intent);
  const challenge=await this.security.findActiveChallenge(userId,purpose);
  if(!challenge){
   await this.security.recordEvent({userId,eventType:"security.device_proof_failed",severity:"warning",metadata:{purpose,reason:"challenge_not_found"}});
   throw Error("DEVICE_PROOF_INVALID");
  }
  if(challenge.deviceId!==input.deviceId){
   await this.recordFailure(userId,input.deviceId,challenge.id,purpose,"device_mismatch");
   throw Error("DEVICE_PROOF_INVALID");
  }
  const suppliedHash=createHash("sha256").update(input.challenge).digest("hex");
  const expectedHash=Buffer.from(challenge.challengeHash,"utf8");
  const receivedHash=Buffer.from(suppliedHash,"utf8");
  if(expectedHash.length!==receivedHash.length||!timingSafeEqual(expectedHash,receivedHash)){
   await this.recordFailure(userId,input.deviceId,challenge.id,purpose,"challenge_invalid");
   throw Error("DEVICE_PROOF_INVALID");
  }
  const signedText = this.signedText(input.challenge, challenge.intentHash, intent);
  if(signedText===null){
   await this.recordFailure(userId,input.deviceId,challenge.id,purpose,"intent_mismatch");
   throw Error("DEVICE_PROOF_INVALID");
  }
  const publicKey=await this.security.getActiveDevicePublicKey(userId,input.deviceId);
  if(!publicKey){
   await this.recordFailure(userId,input.deviceId,challenge.id,purpose,"device_key_unavailable");
   throw Error("DEVICE_PROOF_INVALID");
  }
  let valid=false;
  try{
   const verifier=createVerify("SHA256");
   verifier.update(signedText,"utf8"); verifier.end();
   valid=verifier.verify(publicKey,Buffer.from(input.signature,"base64url"));
  }catch{valid=false}
  if(!valid){
   await this.recordFailure(userId,input.deviceId,challenge.id,purpose,"signature_invalid");
   throw Error("DEVICE_PROOF_INVALID");
  }
  if(!await this.security.consumeChallenge(challenge.id,new Date()))throw Error("DEVICE_PROOF_INVALID");
  await this.security.recordEvent({userId,deviceId:input.deviceId,eventType:"security.device_proof_verified",severity:"info",metadata:{purpose}});
  return true;
 }
 /**
  * When the challenge was issued for a specific intent, the signature must
  * cover the canonical intent so a captured proof cannot be replayed against
  * different transaction parameters. Returns null when the intent does not
  * match the intent the challenge was created for.
  */
 private signedText(challenge:string,intentHash:string|null,intent?:SensitiveIntent):string|null{
  if(intentHash===null)return challenge;
  if(intent===undefined)return null;
  const supplied=hashIntent(intent);
  if(intentHash.length!==supplied.length||!timingSafeEqual(Buffer.from(intentHash,"utf8"),Buffer.from(supplied,"utf8")))return null;
  return `${challenge}.${canonicalizeIntent(intent)}`;
 }
 private async recordFailure(userId:string,deviceId:string,challengeId:string,purpose:StepUpPurpose,reason:string){
  await this.security.incrementChallengeAttempt(challengeId);
  await this.security.recordEvent({userId,deviceId,eventType:"security.device_proof_failed",severity:"warning",metadata:{purpose,reason}});
 }
}