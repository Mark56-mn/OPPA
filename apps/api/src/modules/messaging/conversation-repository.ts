export interface ConversationRepository {
  listForUser(userId:string):Promise<unknown[]>;
  createDirect(userId:string,otherUserId:string):Promise<unknown>;
}
