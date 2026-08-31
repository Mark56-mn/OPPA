import { db } from "../../db/pool.js";
import type { ConversationRepository } from "./conversation-repository.js";
function requireDb(){if(!db) throw new Error("DATABASE_URL is not configured"); return db;}
export class PostgresConversationRepository implements ConversationRepository {
  async listForUser(userId:string){
    const r=await requireDb().query(`
      select c.id,c.kind,c.title,c.created_at as "createdAt",c.updated_at as "updatedAt"
      from public.oppa_conversations c
      join public.oppa_conversation_members m on m.conversation_id=c.id
      where m.user_id=$1 and m.left_at is null
      order by c.updated_at desc`,[userId]); return r.rows;
  }
  async createDirect(userId:string,otherUserId:string){
    if(userId===otherUserId) throw new Error("CONVERSATION_SELF_INVALID");
    const client=await requireDb().connect();
    try{
      await client.query("begin");
      const existing=await client.query(`
        select c.id,c.kind,c.title,c.created_at as "createdAt",c.updated_at as "updatedAt"
        from public.oppa_conversations c
        join public.oppa_conversation_members m1 on m1.conversation_id=c.id and m1.user_id=$1 and m1.left_at is null
        join public.oppa_conversation_members m2 on m2.conversation_id=c.id and m2.user_id=$2 and m2.left_at is null
        where c.kind='direct' limit 1`,[userId,otherUserId]);
      if(existing.rows[0]){await client.query("commit");return existing.rows[0];}
      const c=await client.query(`insert into public.oppa_conversations(kind,created_by) values('direct',$1)
        returning id,kind,title,created_at as "createdAt",updated_at as "updatedAt"`,[userId]);
      const id=c.rows[0].id;
      await client.query(`insert into public.oppa_conversation_members(conversation_id,user_id,role)
        values($1,$2,'owner'),($1,$3,'member')`,[id,userId,otherUserId]);
      await client.query("commit"); return c.rows[0];
    }catch(e){await client.query("rollback");throw e;}finally{client.release();}
  }
}
