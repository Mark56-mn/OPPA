import { db } from "../../db/pool.js";
import type { Message, MessageReceipt, MessageRepository } from "./message-repository.js";
function requireDb(){if(!db) throw new Error("DATABASE_URL is not configured"); return db;}

// Per-member receipt rows are created when a message lands so every member can
// later mark their own copy delivered/read without touching anyone else's.
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
              body, metadata, created_at as "createdAt", edited_at as "editedAt", deleted_at as "deletedAt"
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
    const client=await requireDb().connect();
    try{
      await client.query("begin");
      const r=await client.query(
        `insert into public.oppa_messages
         (conversation_id,sender_user_id,client_message_id,message_type,body,metadata)
         values($1,$2,$3,$4,$5,$6)
         on conflict (sender_user_id,client_message_id) do update set id=public.oppa_messages.id
         returning id, conversation_id as "conversationId", sender_user_id as "senderUserId",
                   client_message_id as "clientMessageId", message_type as "messageType",
                   body, metadata, created_at as "createdAt", edited_at as "editedAt", deleted_at as "deletedAt"`,
        [conversationId,userId,input.clientMessageId ?? null,input.messageType ?? "text",input.body ?? null,input.metadata ?? {}]);
      const message=r.rows[0];
      // Receipt rows for every active member; idempotent on message+user.
      await client.query(
        `insert into public.oppa_message_receipts(message_id,user_id,conversation_id)
         select $1, m.user_id, $2
         from public.oppa_conversation_members m
         where m.conversation_id=$2 and m.left_at is null
         on conflict (message_id,user_id) do nothing`,
        [message.id,conversationId]);
      // Sender's own copy is delivered+read at creation.
      await client.query(
        `update public.oppa_message_receipts
         set delivered_at=coalesce(delivered_at,now()), read_at=coalesce(read_at,now())
         where message_id=$1 and user_id=$2`,
        [message.id,userId]);
      await client.query(
        `update public.oppa_conversations set updated_at=now() where id=$1`,
        [conversationId]);
      await client.query("commit");
      return message;
    }catch(e){await client.query("rollback");throw e;}finally{client.release();}
  }
  async markRead(conversationId:string,userId:string,upToMessageId?:string){
    if(!(await this.isMember(conversationId,userId))) throw new Error("FORBIDDEN");
    const r=await requireDb().query(
      `update public.oppa_message_receipts r
       set delivered_at=coalesce(r.delivered_at,now()),
           read_at=coalesce(r.read_at,now())
       from public.oppa_messages m
       where r.message_id=m.id
         and r.conversation_id=$1 and r.user_id=$2
         and r.read_at is null
         and m.sender_user_id <> $2
         and ($3::uuid is null or m.created_at <= (select created_at from public.oppa_messages where id=$3 and conversation_id=$1))`,
      [conversationId,userId,upToMessageId ?? null]);
    return r.rowCount ?? 0;
  }
  async receipts(conversationId:string,messageId:string,userId:string):Promise<MessageReceipt[]>{
    if(!(await this.isMember(conversationId,userId))) throw new Error("FORBIDDEN");
    const r=await requireDb().query(
      `select rc.user_id as "userId", rc.delivered_at as "deliveredAt", rc.read_at as "readAt"
       from public.oppa_message_receipts rc
       where rc.message_id=$1 and rc.conversation_id=$2
       order by rc.read_at is null, rc.user_id`,
      [messageId,conversationId]);
    return r.rows;
  }
  async edit(conversationId:string,messageId:string,userId:string,body:string){
    if(!(await this.isMember(conversationId,userId))) throw new Error("FORBIDDEN");
    if(!body?.trim()) throw new Error("MESSAGE_BODY_REQUIRED");
    if(body.length>10000) throw new Error("MESSAGE_TOO_LONG");
    const r=await requireDb().query(
      `update public.oppa_messages
       set body=$4, edited_at=now()
       where id=$1 and conversation_id=$2 and sender_user_id=$3
         and deleted_at is null and message_type='text'
       returning id, conversation_id as "conversationId", sender_user_id as "senderUserId",
                 client_message_id as "clientMessageId", message_type as "messageType",
                 body, metadata, created_at as "createdAt", edited_at as "editedAt", deleted_at as "deletedAt"`,
      [messageId,conversationId,userId,body]);
    return r.rows[0] ?? null;
  }
  async remove(conversationId:string,messageId:string,userId:string){
    if(!(await this.isMember(conversationId,userId))) throw new Error("FORBIDDEN");
    const r=await requireDb().query(
      `update public.oppa_messages
       set deleted_at=now()
       where id=$1 and conversation_id=$2 and sender_user_id=$3 and deleted_at is null`,
      [messageId,conversationId,userId]);
    return Boolean(r.rowCount);
  }
  async unreadCounts(userId:string){
    const r=await requireDb().query(
      `select r.conversation_id as "conversationId", count(*)::int as unread
       from public.oppa_message_receipts r
       where r.user_id=$1 and r.read_at is null
         and exists (select 1 from public.oppa_messages m where m.id=r.message_id and m.deleted_at is null and m.sender_user_id <> $1)
       group by r.conversation_id`,
      [userId]);
    return r.rows;
  }
}
