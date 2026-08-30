import { db } from "../../db/pool.js";
import type { MessageRepository } from "./message-repository.js";
function requireDb(){if(!db) throw new Error("DATABASE_URL is not configured"); return db;}

export class PostgresMessageRepository implements MessageRepository {
  async isMember(conversationId:string,userId:string){
    const r=await requireDb().query(
      `select 1 from public.oppa_conversation_members where conversation_id=$1 and user_id=$2 and left_at is null`,
      [conversationId,userId]); return Boolean(r.rowCount);
  }
  async list(conversationId:string,userId:string,limit:number,before?:string){
    if(!(await this.isMember(conversationId,userId))) throw new Error("FORBIDDEN");
    const r=await requireDb().query(
      `select id, conversation_id as "conversationId", sender_user_id as "senderUserId",
              client_message_id as "clientMessageId", message_type as "messageType",
              body, metadata, created_at as "createdAt"
       from public.oppa_messages
       where conversation_id=$1 and deleted_at is null
         and ($3::timestamptz is null or created_at < $3)
       order by created_at desc limit $2`,
      [conversationId, Math.min(Math.max(limit,1),100), before ?? null]);
    return r.rows;
  }
  async send(conversationId:string,userId:string,input:{body?:string;messageType?:string;metadata?:Record<string,unknown>;clientMessageId?:string}){
    if(!(await this.isMember(conversationId,userId))) throw new Error("FORBIDDEN");
    if(input.messageType === "text" && !input.body?.trim()) throw new Error("MESSAGE_BODY_REQUIRED");
    if((input.body?.length ?? 0)>10000) throw new Error("MESSAGE_TOO_LONG");
    const r=await requireDb().query(
      `insert into public.oppa_messages
       (conversation_id,sender_user_id,client_message_id,message_type,body,metadata)
       values($1,$2,$3,$4,$5,$6)
       on conflict (sender_user_id,client_message_id) do update set id=public.oppa_messages.id
       returning id, conversation_id as "conversationId", sender_user_id as "senderUserId",
                 client_message_id as "clientMessageId", message_type as "messageType",
                 body, metadata, created_at as "createdAt"`,
      [conversationId,userId,input.clientMessageId ?? null,input.messageType ?? "text",input.body ?? null,input.metadata ?? {}]);
    return r.rows[0];
  }
}
