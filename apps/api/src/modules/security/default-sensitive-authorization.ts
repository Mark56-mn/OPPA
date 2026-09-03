import { DeviceProofService } from "./device-proof-service.js";
import type { SensitiveAuthorization, AuthorizationProof, SensitiveOperation } from "./sensitive-authorization.js";
import type { SensitiveIntent } from "./intent-binding.js";
export class DefaultSensitiveAuthorization implements SensitiveAuthorization{
 constructor(private readonly proofs:DeviceProofService){}
 async authorize(input:{userId:string;operation:SensitiveOperation;proof:AuthorizationProof;intent?:SensitiveIntent}){
  await this.proofs.verify(input.userId,input.operation,input.proof,input.intent);
  return true;
 }
}