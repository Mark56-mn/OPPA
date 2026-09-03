export type StepUpPurpose="wallet_transfer"|"payment_reversal"|"security_change"|"account_recovery";
export type StepUpChallenge={id:string;userId:string;deviceId:string|null;purpose:StepUpPurpose;challengeHash:string;intentHash:string|null};
export interface SecurityRepository{
 isActiveDevice(userId:string,deviceId:string):Promise<boolean>;
 createChallenge(input:{userId:string;deviceId:string;purpose:StepUpPurpose;challengeHash:string;expiresAt:Date;maxAttempts:number;intentHash?:string|null}):Promise<void>;
 findActiveChallenge(userId:string,purpose:StepUpPurpose):Promise<StepUpChallenge|null>;
 incrementChallengeAttempt(id:string):Promise<void>;
 consumeChallenge(id:string,now:Date):Promise<boolean>;
 recordEvent(input:{userId?:string;deviceId?:string;sessionId?:string;eventType:string;severity:"info"|"warning"|"critical";metadata?:Record<string,unknown>}):Promise<void>;
}