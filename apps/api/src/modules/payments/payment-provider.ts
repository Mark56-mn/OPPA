export type PaymentProviderName="paystack"|"flutterwave";
export type VerifiedPayment={reference:string;transactionId:string;amountMinor:number;currency:"NGN";status:"success"|"failed"};
export type ReversalResult={providerReversalId?:string;status:"completed"|"pending"};
export interface PaymentProvider{
 readonly name:PaymentProviderName;
 initialize(input:{amountMinor:number;email:string;reference:string;callbackUrl?:string}):Promise<{authorizationUrl:string}>;
 verify(reference:string):Promise<VerifiedPayment>;
 verifyWebhook(rawBody:Buffer,signature:string|undefined):boolean;
 reverse?(input:{transactionId:string;reference:string;amountMinor:number}):Promise<ReversalResult>;
}