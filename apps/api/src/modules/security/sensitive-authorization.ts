import type { StepUpPurpose } from "./security-repository.js";
export type SensitiveOperation="wallet_transfer"|"payment_reversal"|"security_change"|"account_recovery";
export type AuthorizationProof={deviceId:string;challenge:string;signature:string};
export interface SensitiveAuthorization{
 authorize(input:{userId:string;operation:SensitiveOperation;proof:AuthorizationProof}):Promise<boolean>;
}
export function assertSensitiveOperation(value:string):SensitiveOperation{
 if(value==="wallet_transfer"||value==="payment_reversal"||value==="security_change"||value==="account_recovery")return value;
 throw Error("SENSITIVE_OPERATION_INVALID");
}
