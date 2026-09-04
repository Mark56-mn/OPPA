import { Router } from "express";
import type { PaymentService } from "./payment-service.js";
import type { PaymentRepository } from "./payment-repository.js";
import { db } from "../../db/pool.js";

export function createPaymentRouter(service:PaymentService,paymentRepository?:PaymentRepository){
 const router=Router();
 router.post("/initialize",async(req,res,next)=>{try{
   const provider=req.body?.provider; const amountMinor=req.body?.amountMinor; const email=req.body?.email;
   if(provider!=="paystack"&&provider!=="flutterwave") throw new Error("PAYMENT_PROVIDER_INVALID");
   const callbackUrl=typeof req.body?.callbackUrl==="string"?req.body.callbackUrl:undefined;
   const result=await service.initialize({userId:req.auth!.userId,provider,amountMinor,email,callbackUrl});
   res.status(201).json(result);
 }catch(e){next(e)}});
 router.post("/reverse",async(req,res,next)=>{try{
   const paymentId=typeof req.body?.paymentId==="string"?req.body.paymentId:"";
   const reason=typeof req.body?.reason==="string"?req.body.reason:"";
   if(!paymentId) throw Error("PAYMENT_NOT_FOUND");
   if(!reason) throw Error("PAYMENT_REVERSAL_REASON_INVALID");
   const proof={deviceId:typeof req.body?.deviceId==="string"?req.body.deviceId:"",challenge:typeof req.body?.challenge==="string"?req.body.challenge:"",signature:typeof req.body?.signature==="string"?req.body.signature:""};
   res.status(200).json(await service.reverse(req.auth!.userId,paymentId,proof,reason));
 }catch(e){next(e)}});
 router.get("/history",async(req,res,next)=>{try{
   if(!db) throw Error("DATABASE_URL is not configured");
   const rawLimit=Number(req.query.limit??20); const rawOffset=Number(req.query.offset??0);
   if(!Number.isInteger(rawLimit)||rawLimit<1||rawLimit>50||!Number.isInteger(rawOffset)||rawOffset<0) throw Error("PAYMENT_PAGINATION_INVALID");
   if(paymentRepository){
     res.json({payments:await paymentRepository.list(req.auth!.userId,rawLimit,rawOffset)});
   } else {
     const q=await db.query(`select id,provider,reference,amount_minor as "amountMinor",currency,status,risk_score as "riskScore",risk_decision as "riskDecision",authorization_url as "authorizationUrl",created_at as "createdAt",paid_at as "paidAt" from public.oppa_payments where user_id=$1 order by created_at desc limit $2 offset $3`,[req.auth!.userId,rawLimit,rawOffset]);
     res.json({payments:q.rows});
   }
 }catch(e){next(e)}});
 return router;
}