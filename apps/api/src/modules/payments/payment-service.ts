import { randomUUID } from "node:crypto";
import type { PaymentProvider } from "./payment-provider.js";
import type { PaymentRepository, PaymentRecord } from "./payment-repository.js";
export class PaymentService {
  constructor(private readonly repo:PaymentRepository, private readonly providers:Record<"paystack"|"flutterwave",PaymentProvider>) {}
  async initialize(input:{userId:string;provider:"paystack"|"flutterwave";amountMinor:number;email:string;callbackUrl?:string}) {
    if (!Number.isSafeInteger(input.amountMinor)||input.amountMinor<=0) throw new Error("PAYMENT_AMOUNT_INVALID");
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(input.email)) throw new Error("PAYMENT_EMAIL_INVALID");
    const reference=`OPPA_${Date.now()}_${randomUUID().replaceAll("-","")}`;
    const result=await this.providers[input.provider].initialize({amountMinor:input.amountMinor,email:input.email,reference,callbackUrl:input.callbackUrl});
    return this.repo.create({userId:input.userId,provider:input.provider,reference,amountMinor:input.amountMinor,authorizationUrl:result.authorizationUrl});
  }
  async handleWebhook(provider:"paystack"|"flutterwave",rawBody:Buffer,signature:string|undefined) {
    const p=this.providers[provider];
    if (!p.verifyWebhook(rawBody,signature)) throw new Error("PAYMENT_WEBHOOK_INVALID");
    const body:any=JSON.parse(rawBody.toString("utf8"));
    const reference=provider==="paystack"?body?.data?.reference:body?.data?.tx_ref;
    if (typeof reference!=="string"||reference.length>160) throw new Error("PAYMENT_REFERENCE_INVALID");
    const verified=await p.verify(reference);
    if (verified.status!=="success") { await this.repo.markFailed(provider,reference); return {status:"failed"}; }
    const payment=await this.repo.markPaidAndCredit({provider,reference:verified.reference,transactionId:verified.transactionId,amountMinor:verified.amountMinor});
    return {status:"paid",payment};
  }
}