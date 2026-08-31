import { randomUUID } from "node:crypto";
import { db } from "../../db/pool.js";
import type { DevicePlatform, DeviceRepository } from "./device-repository.js";
function requireDb(){if(!db) throw new Error("DATABASE_URL is not configured");return db;}
export class PostgresDeviceRepository implements DeviceRepository{
 async register(input:{userId:string;publicKey:string;platform:DevicePlatform}){
  const id=randomUUID();
  const r=await requireDb().query(`insert into public.oppa_devices(id,user_id,device_public_key,platform)
   values($1,$2,$3,$4)
   on conflict(user_id,device_public_key) do update set status='active',platform=excluded.platform,last_seen_at=now()
   returning id`,[id,input.userId,input.publicKey,input.platform]);
  return {id:r.rows[0].id};
 }
 async revoke(deviceId:string,userId:string){await requireDb().query(`update public.oppa_devices set status='revoked' where id=$1 and user_id=$2 and status='active'`,[deviceId,userId]);}
}