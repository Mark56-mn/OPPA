import { Router } from "express";
import type { ConversationRepository } from "./conversation-repository.js";
import { requireJsonBody } from "../../http/validate.js";
export function createConversationRouter(conversations:ConversationRepository){
 const router=Router();
 router.get("/",async(req,res,next)=>{try{res.json({conversations:await conversations.listForUser(req.auth!.userId)});}catch(e){next(e);}});
 router.post("/direct",requireJsonBody,async(req,res,next)=>{
  try{const other=req.body?.userId;if(typeof other!=="string"){res.status(400).json({error:"USER_ID_REQUIRED",requestId:res.locals.requestId});return;}
  res.status(201).json(await conversations.createDirect(req.auth!.userId,other));}catch(e){next(e);}
 });
 return router;
}
