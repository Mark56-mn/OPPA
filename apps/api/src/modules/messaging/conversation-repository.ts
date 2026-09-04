export interface ConversationRepository {
  listForUser(userId:string):Promise<unknown[]>;
  createDirect(userId:string,otherUserId:string):Promise<unknown>;
  createGroup(userId:string,title:string,memberUserIds:string[]):Promise<unknown>;
  addMember(conversationId:string,actorId:string,newMemberId:string):Promise<{ok:boolean}>;
  leave(conversationId:string,userId:string):Promise<{ok:boolean}>;
}
