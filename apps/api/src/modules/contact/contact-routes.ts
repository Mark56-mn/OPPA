import { Router } from "express";
import type { ContactRepository } from "./contact-repository.js";
import { requireJsonBody } from "../../http/validate.js";
export function createContactRouter(contacts:ContactRepository){
 const router=Router();
 router.get("/",async(req,res,next)=>{try{res.json({contacts:await contacts.list(req.auth!.userId)});}catch(e){next(e);}});
 router.post("/",requireJsonBody,async(req,res,next)=>{try{const {userId,nickname}=req.body??{};if(typeof userId!=="string"){res.status(400).json({error:"USER_ID_REQUIRED",requestId:res.locals.requestId});return;}res.status(201).json(await contacts.add(req.auth!.userId,userId,nickname));}catch(e){next(e);}});
 router.delete("/:userId",async(req,res,next)=>{try{await contacts.remove(req.auth!.userId,req.params.userId);res.status(204).send();}catch(e){next(e);}});
 router.post("/:userId/block",async(req,res,next)=>{try{await contacts.block(req.auth!.userId,req.params.userId);res.status(204).send();}catch(e){next(e);}});
 return router;
}
