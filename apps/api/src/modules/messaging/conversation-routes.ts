import { Router } from "express";
import type { ConversationRepository } from "./conversation-repository.js";
import type { MessageRepository } from "./message-repository.js";
import { requireJsonBody } from "../../http/validate.js";
export function createConversationRouter(conversations:ConversationRepository,messages?:MessageRepository){
 const router=Router();
 router.get("/",async(req,res,next)=>{try{res.json({conversations:await conversations.listForUser(req.auth!.userId)});}catch(e){next(e);}});
 router.post("/direct",requireJsonBody,async(req,res,next)=>{
  try{const other=req.body?.userId;if(typeof other!=="string"){res.status(400).json({error:"USER_ID_REQUIRED",requestId:res.locals.requestId});return;}
  res.status(201).json(await conversations.createDirect(req.auth!.userId,other));}catch(e){next(e);}
 });
 router.post("/groups",requireJsonBody,async(req,res,next)=>{
  try{
    const title=typeof req.body?.title==="string"?req.body.title:"";
    const rawMembers=req.body?.memberUserIds;
    if(!title.trim()||title.length>120){res.status(400).json({error:"CONVERSATION_TITLE_INVALID",requestId:res.locals.requestId});return;}
    if(!Array.isArray(rawMembers)||rawMembers.length<1||rawMembers.length>200||rawMembers.some((m:unknown)=>typeof m!=="string"||m.length>128)){
      res.status(400).json({error:"CONVERSATION_MEMBERS_INVALID",requestId:res.locals.requestId});return;
    }
    res.status(201).json(await conversations.createGroup(req.auth!.userId,title.trim(),rawMembers));
  }catch(e){next(e);}
 });
 router.post("/:conversationId/members",requireJsonBody,async(req,res,next)=>{
  try{
    const conversationId=String(req.params.conversationId);
    const member=typeof req.body?.userId==="string"?req.body.userId:"";
    if(!conversationId||conversationId.length>128||!member||member.length>128){
      res.status(400).json({error:"USER_ID_REQUIRED",requestId:res.locals.requestId});return;
    }
    res.status(201).json(await conversations.addMember(conversationId,req.auth!.userId,member));
  }catch(e){next(e);}
 });
 router.post("/:conversationId/leave",async(req,res,next)=>{
  try{
    const conversationId=String(req.params.conversationId);
    if(!conversationId||conversationId.length>128){res.status(400).json({error:"CONVERSATION_NOT_FOUND",requestId:res.locals.requestId});return;}
    res.status(200).json(await conversations.leave(conversationId,req.auth!.userId));
  }catch(e){next(e);}
 });
 // Per-conversation unread count (cheap poll for chat lists).
 router.get("/:conversationId/unread",async(req,res,next)=>{
  try{
    const conversationId=String(req.params.conversationId);
    if(!messages) throw new Error("INTERNAL_SERVER_ERROR");
    if(!(await messages.isMember(conversationId,req.auth!.userId))) throw new Error("FORBIDDEN");
    const counts=await messages.unreadCounts(req.auth!.userId);
    res.json({unread:counts.find(c=>c.conversationId===conversationId)?.unread ?? 0});
  }catch(e){next(e);}
 });
 return router;
}
