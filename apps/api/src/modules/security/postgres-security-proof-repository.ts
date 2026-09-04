import { db } from "../../db/pool.js";
import type { SecurityProofRepository } from "./device-proof-service.js";
import type { StepUpChallenge, StepUpPurpose } from "./security-repository.js";
export class PostgresSecurityProofRepository implements SecurityProofRepository{
 // Optional injection point for tests; production uses the shared pool.
 constructor(private readonly pool?: typeof db){}
 private require(){
  const d=this.pool??db;
  if(!d)throw Error("DATABASE_URL is not configured");
  return d;
 }
 async isActiveDevice(userId:string,deviceId:string){const r=await this.require().query("select 1 from public.oppa_devices where id=$1 and user_id=$2 and status='active' limit 1",[deviceId,userId]);return r.rowCount===1}
 async createChallenge(i:{userId:string;deviceId:string;purpose:StepUpPurpose;challengeHash:string;expiresAt:Date;maxAttempts:number;intentHash?:string|null}){
  // Consume-then-insert must be transactional: if the insert failed after a
  // non-transactional consume, the user would be left with NO active challenge
  // and no way to obtain one until expiry (step-up self-denial).
  const d=this.require();
  const client=await d.connect();
  try{
   await client.query("begin");
   await client.query("update public.oppa_step_up_challenges set consumed_at=now() where user_id=$1 and purpose=$2 and consumed_at is null",[i.userId,i.purpose]);
   try{
    await client.query("insert into public.oppa_step_up_challenges(user_id,device_id,purpose,challenge_hash,expires_at,max_attempts,intent_hash) values($1,$2,$3,$4,$5,$6,$7)",[i.userId,i.deviceId,i.purpose,i.challengeHash,i.expiresAt,i.maxAttempts,i.intentHash??null]);
   }catch(e:any){
    if(e?.code==="23505")throw Error("STEP_UP_CHALLENGE_CONFLICT");
    throw e;
   }
   await client.query("commit");
  }catch(e){
   try{await client.query("rollback")}catch{}
   throw e;
  }finally{
   client.release();
  }
 }
 async findActiveChallenge(userId:string,purpose:StepUpPurpose):Promise<StepUpChallenge|null>{const r=await this.require().query("select id,user_id as \"userId\",device_id as \"deviceId\",purpose,challenge_hash as \"challengeHash\",intent_hash as \"intentHash\" from public.oppa_step_up_challenges where user_id=$1 and purpose=$2 and consumed_at is null and expires_at>now() and attempts<max_attempts order by created_at desc limit 1",[userId,purpose]);return r.rows[0]??null}
 async incrementChallengeAttempt(id:string){await this.require().query("update public.oppa_step_up_challenges set attempts=attempts+1 where id=$1 and consumed_at is null and attempts<max_attempts",[id])}
 async consumeChallenge(id:string,now:Date){const r=await this.require().query("update public.oppa_step_up_challenges set consumed_at=$2 where id=$1 and consumed_at is null and expires_at>$2 and attempts<max_attempts returning id",[id,now]);return r.rowCount===1}
 async recordEvent(i:any){await this.require().query("insert into public.oppa_security_events(user_id,device_id,session_id,event_type,severity,metadata) values($1,$2,$3,$4,$5,$6::jsonb)",[i.userId??null,i.deviceId??null,i.sessionId??null,i.eventType,i.severity,JSON.stringify(i.metadata??{})])}
 async getActiveDevicePublicKey(userId:string,deviceId:string){const r=await this.require().query("select device_public_key from public.oppa_devices where id=$1 and user_id=$2 and status='active' limit 1",[deviceId,userId]);return r.rows[0]?.device_public_key??null}
}