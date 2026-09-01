import { Router } from "express";
import type { PaymentService } from "./payment-service.js";
export function createPaymentRouter(service:PaymentService){
 const router=Router();
 router.post("/initialize",async(req,res,next)=>{try{
   const provider=req.body?.provider; const amountMinor=req.body?.amountMinor; const email=req.body?.email;
   if(provider!=="paystack"&&provider!=="flutterwave") throw new Error("PAYMENT_PROVIDER_INVALID");
   const callbackUrl=typeof req.body?.callbackUrl==="string"?req.body.callbackUrl:undefined;
   const result=await service.initialize({userId:req.auth!.userId,provider,amountMinor,email,callbackUrl});
   res.status(201).json(result);
 }catch(e){next(e)}});
 return router;
}