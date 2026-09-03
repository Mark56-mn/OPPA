import { Router } from "express";
import type { PaymentService } from "./payment-service.js";

export function createPaymentWebhookRouter(service:PaymentService){
 const router=Router();
 for(const provider of ["paystack","flutterwave"] as const){
  router.post(`/${provider}`,async(req,res,next)=>{try{
    const raw=(req as any).rawBody as Buffer|undefined;
    if(!raw) throw Error("PAYMENT_WEBHOOK_BODY_MISSING");
    const signature=provider==="paystack"?req.header("x-paystack-signature")??undefined:req.header("verif-hash")??undefined;
    const result=await service.handleWebhook(provider,raw,signature);
    res.status(200).json(result);
  }catch(e){next(e)}});
 }
 // Provider reversals are intentionally not exposed here until an authenticated,
 // provider-backed reversal workflow is implemented. Never leave a mutating reversal
 // endpoint on the unauthenticated webhook surface.
 return router;
}
