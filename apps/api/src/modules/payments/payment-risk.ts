export type RiskDecision = "allow" | "review" | "block";
export type RiskResult = { score:number; decision:RiskDecision; reasons:string[] };
export function evaluatePaymentRisk(input:{amountMinor:number;recentPaidCount:number;recentFailedCount:number}):RiskResult {
 let score=0; const reasons:string[]=[];
 if(input.amountMinor>=50000000){score+=35;reasons.push("LARGE_AMOUNT");}
 else if(input.amountMinor>=20000000){score+=15;reasons.push("ELEVATED_AMOUNT");}
 if(input.recentPaidCount>=5){score+=20;reasons.push("HIGH_PAYMENT_FREQUENCY");}
 if(input.recentFailedCount>=3){score+=30;reasons.push("RECENT_PAYMENT_FAILURES");}
 return {score,decision:score>=70?"block":score>=40?"review":"allow",reasons};
}