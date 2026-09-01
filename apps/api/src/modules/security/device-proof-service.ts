import { createVerify } from "node:crypto";
import type { SecurityRepository, StepUpPurpose } from "./security-repository.js";

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
 async verify(userId:string,purpose:StepUpPurpose,input:DeviceProof){
  if(!input.deviceId||!input.challenge||!input.signature||input.signature.length>8192)throw Error("DEVICE_PROOF_INVALID");
  const challenge=await this.security.findActiveChallenge(userId,purpose);
  if(!challenge||challenge.deviceId!==input.deviceId)throw Error("DEVICE_PROOF_INVALID");
  const publicKey=await this.security.getActiveDevicePublicKey(userId,input.deviceId);
  if(!publicKey)throw Error("DEVICE_PROOF_INVALID");
  let valid=false;
  try{
   const verifier=createVerify("SHA256");
   verifier.update(input.challenge,"utf8"); verifier.end();
   valid=verifier.verify(publicKey,Buffer.from(input.signature,"base64url"));
  }catch{valid=false}
  if(!valid)throw Error("DEVICE_PROOF_INVALID");
  return this.security.consumeStepUp(userId,input.challenge,purpose);
 }
}
