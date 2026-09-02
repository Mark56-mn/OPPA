export type PaymentRecord={id:string;userId:string;provider:"paystack"|"flutterwave";reference:string;providerTransactionId:string|null;amountMinor:number;currency:"NGN";status:"pending"|"paid"|"failed"|"reversed";authorizationUrl:string|null;riskScore?:number|null;riskDecision?:"allow"|"review"|"block"|null;createdAt?:string;paidAt?:string|null};
export type RecentPaymentStats={paidCount:number;failedCount:number};
export interface PaymentRepository{
 create(input:any):Promise<PaymentRecord>;
 find(userId:string,reference:string):Promise<PaymentRecord|null>;
 findByProviderReference(provider:"paystack"|"flutterwave",reference:string):Promise<PaymentRecord|null>;
 list(userId:string,limit:number,offset:number):Promise<PaymentRecord[]>;
 recentPaymentStats(userId:string,since:Date):Promise<RecentPaymentStats>;
 setRisk(id:string,score:number,decision:"allow"|"review"|"block",reasons:string[]):Promise<PaymentRecord>;
 markPaidAndCredit(input:any):Promise<PaymentRecord>;
 markFailed(provider:"paystack"|"flutterwave",reference:string):Promise<void>;
 reverseAndDebit(input:{paymentId:string;reason:string;providerReversalId?:string}):Promise<PaymentRecord>;
}
