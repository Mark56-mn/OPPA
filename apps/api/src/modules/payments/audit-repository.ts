import { db } from "../../db/pool.js";
export async function writeAuditEvent(input:{actorUserId?:string;eventType:string;entityType:string;entityId?:string;requestId?:string;ipHash?:string;metadata?:Record<string,unknown>}) {
 if(!db) throw new Error("DATABASE_URL is not configured");
 await db.query(`insert into public.oppa_audit_events(actor_user_id,event_type,entity_type,entity_id,request_id,ip_hash,metadata) values($1,$2,$3,$4,$5,$6,$7::jsonb)`,
 [input.actorUserId??null,input.eventType,input.entityType,input.entityId??null,input.requestId??null,input.ipHash??null,JSON.stringify(input.metadata??{})]);
}