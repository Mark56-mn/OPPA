import { db } from "../../db/pool.js";
import type { ConversationRepository } from "./conversation-repository.js";
function requireDb(){if(!db) throw new Error("DATABASE_URL is not configured"); return db;}

export class PostgresConversationRepository implements ConversationRepository {
  async listForUser(userId:string){
    const r=await requireDb().query(`
      select c.id,c.kind,c.title,c.created_at as "createdAt",c.updated_at as "updatedAt",
        (select count(*)::int from public.oppa_conversation_members m2
          where m2.conversation_id=c.id and m2.left_at is null) as "memberCount",
        (select count(*)::int from public.oppa_message_receipts rc
          where rc.conversation_id=c.id and rc.user_id=$1 and rc.read_at is null
            and exists (select 1 from public.oppa_messages m3
                        where m3.id=rc.message_id and m3.deleted_at is null and m3.sender_user_id<>$1)) as "unreadCount"
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
  async createGroup(userId:string,title:string,memberUserIds:string[]){
    const client=await requireDb().connect();
    try{
      await client.query("begin");
      const c=await client.query(
        `insert into public.oppa_conversations(kind,title,created_by) values('group',$1,$2)
         returning id,kind,title,created_at as "createdAt",updated_at as "updatedAt"`,
        [title,userId]);
      const id=c.rows[0].id;
      const members=new Set(memberUserIds.filter(u=>u&&u!==userId));
      await client.query(
        `insert into public.oppa_conversation_members(conversation_id,user_id,role)
         values($1,$2,'owner')`,[id,userId]);
      for(const member of members){
        // Fail with USER_NOT_FOUND if a member does not exist; FK also guards.
        const exists=await client.query(`select 1 from public.oppa_users where id=$1`,[member]);
        if(!exists.rows[0]) throw new Error("USER_NOT_FOUND");
        await client.query(
          `insert into public.oppa_conversation_members(conversation_id,user_id,role)
           values($1,$2,'member') on conflict do nothing`,[id,member]);
      }
      await client.query("commit"); return c.rows[0];
    }catch(e){await client.query("rollback");throw e;}finally{client.release();}
  }
  async addMember(conversationId:string,actorId:string,newMemberId:string){
    const client=await requireDb().connect();
    try{
      await client.query("begin");
      // Only owners/admins of a group can add members.
      const role=await client.query(
        `select role from public.oppa_conversation_members
         where conversation_id=$1 and user_id=$2 and left_at is null for update`,
        [conversationId,actorId]);
      if(!role.rows[0]) throw new Error("FORBIDDEN");
      if(!["owner","admin"].includes(role.rows[0].role)) throw new Error("FORBIDDEN");
      const kind=await client.query(`select kind from public.oppa_conversations where id=$1`,[conversationId]);
      if(kind.rows[0]?.kind!=="group") throw new Error("CONVERSATION_MEMBERS_INVALID");
      const exists=await client.query(`select 1 from public.oppa_users where id=$1`,[newMemberId]);
      if(!exists.rows[0]) throw new Error("USER_NOT_FOUND");
      await client.query(
        `insert into public.oppa_conversation_members(conversation_id,user_id,role)
         values($1,$2,'member') on conflict (conversation_id,user_id)
         do update set left_at=null, joined_at=now()`,
        [conversationId,newMemberId]);
      await client.query(`update public.oppa_conversations set updated_at=now() where id=$1`,[conversationId]);
      await client.query("commit"); return {ok:true};
    }catch(e){await client.query("rollback");throw e;}finally{client.release();}
  }
  async leave(conversationId:string,userId:string){
    const client=await requireDb().connect();
    try{
      await client.query("begin");
      const r=await client.query(
        `update public.oppa_conversation_members set left_at=now()
         where conversation_id=$1 and user_id=$2 and left_at is null returning user_id`,
        [conversationId,userId]);
      if(!r.rows[0]) throw new Error("FORBIDDEN");
      await client.query(`update public.oppa_conversations set updated_at=now() where id=$1`,[conversationId]);
      await client.query("commit"); return {ok:true};
    }catch(e){await client.query("rollback");throw e;}finally{client.release();}
  }
}
