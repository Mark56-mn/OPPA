import { db } from "../../db/pool.js";
import type { ContactRepository } from "./contact-repository.js";
function requireDb(){if(!db) throw new Error("DATABASE_URL is not configured");return db;}
export class PostgresContactRepository implements ContactRepository{
 async list(userId:string){const r=await requireDb().query(`
  select c.contact_user_id as "userId",u.phone_e164 as phone,c.nickname,c.blocked_at as "blockedAt"
  from public.oppa_contacts c join public.oppa_users u on u.id=c.contact_user_id
  where c.user_id=$1 order by c.created_at desc`,[userId]);return r.rows;}
 async add(userId:string,contactUserId:string,nickname?:string){
  if(userId===contactUserId)throw new Error("CONTACT_SELF_INVALID");
  const r=await requireDb().query(`insert into public.oppa_contacts(user_id,contact_user_id,nickname)
   select $1,$2,$3 where exists(select 1 from public.oppa_users where id=$2 and status='active')
   on conflict(user_id,contact_user_id) do update set nickname=excluded.nickname
   returning contact_user_id as "userId",nickname`,[userId,contactUserId,nickname??null]);
  if(!r.rows[0])throw new Error("USER_NOT_FOUND");return r.rows[0];
 }
 async remove(userId:string,contactUserId:string){await requireDb().query("delete from public.oppa_contacts where user_id=$1 and contact_user_id=$2",[userId,contactUserId]);}
 async block(userId:string,contactUserId:string){await requireDb().query(`insert into public.oppa_contacts(user_id,contact_user_id,blocked_at) values($1,$2,now())
  on conflict(user_id,contact_user_id) do update set blocked_at=now()`,[userId,contactUserId]);}
}
