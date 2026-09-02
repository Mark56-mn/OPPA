import { Router } from "express";
import type { SecurityService } from "./security-service.js";
import { assertSensitiveOperation } from "./sensitive-authorization.js";
import type { AuthorizationContext } from "./authorization-context.js";

function parseContext(value:unknown):AuthorizationContext{
 if(value===undefined)return {};
 if(value===null||typeof value!=="object"||Array.isArray(value))throw Error("SENSITIVE_CONTEXT_INVALID");
 const entries=Object.entries(value as Record<string,unknown>);
 if(entries.length>32)throw Error("SENSITIVE_CONTEXT_INVALID");
 const out:AuthorizationContext={};
 for(const [key,v] of entries){
  if(key.length>128 || !/^[A-Za-z0-9_.:-]+$/.test(key))throw Error("SENSITIVE_CONTEXT_INVALID");
  if(typeof v!=="string"&&typeof v!=="number"&&typeof v!=="boolean"&&v!==null)throw Error("SENSITIVE_CONTEXT_INVALID");
  if(typeof v==="string"&&v.length>512)throw Error("SENSITIVE_CONTEXT_INVALID");
  if(typeof v==="number"&&!Number.isSafeInteger(v))throw Error("SENSITIVE_CONTEXT_INVALID");
  out[key]=v;
 }
 return out;
}

export function createSecurityRouter(security: SecurityService) {
 const router=Router();
 router.post("/step-up/challenge",async(req,res,next)=>{
  try{
   const purpose=assertSensitiveOperation(typeof req.body?.purpose==="string"?req.body.purpose:"");
   const deviceId=typeof req.body?.deviceId==="string"?req.body.deviceId:"";
   if(!deviceId||deviceId.length>128)throw Error("DEVICE_ID_INVALID");
   const context=parseContext(req.body?.context);
   res.status(201).json(await security.createStepUp(req.auth!.userId,purpose,deviceId,context));
  }catch(e){next(e)}
 });
 return router;
}
