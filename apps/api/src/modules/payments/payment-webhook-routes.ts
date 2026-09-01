import { Router } from "express";
import type { PaymentService } from "./payment-service.js";
import { db } from "../../db/pool.js";
export function createPaymentWebhookRouter(service:PaymentService){
 const router=Router();
 for(const provider of ["paystack","flutterwave"] as const){
  router.post(`/${provider}`,async(req,res,next)=>{try{
    const raw=(req as any).rawBody as Buffer|undefined; if(!raw) throw Error("PAYMENT_WEBHOOK_BODY_MISSING");
    const signature=provider==="paystack"?req.header("x-paystack-signature")??undefined:req.header("verif-hash")??undefined;
    const result=await service.handleWebhook(provider,raw,signature); res.status(200).json(result);
  }catch(e){next(e)}});
 }
 router.post("/:provider/reverse",async(req,res,next)=>{try{
   if(req.params.provider!=="paystack"&&req.params.provider!=="flutterwave") throw Error("PAYMENT_PROVIDER_INVALID");
   if(!db) throw Error("DATABASE_URL is not configured");
   res.status(501).json({error:"PAYMENT_REVERSAL_NOT_IMPLEMENTED"});
 }catch(e){next(e)}});
 return router;
}