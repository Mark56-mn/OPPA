import { Router } from "express";
import { db } from "../../db/pool.js";
import { requirePermission } from "./rbac.js";
export function createAdminRouter(){
 const r=Router();
 r.get("/me/permissions",requirePermission("users.read"),async(req:any,res,next)=>{try{
  if(!db)throw Error("DATABASE_URL is not configured");
  const q=await db.query(`select distinct p.code from public.oppa_staff s join public.oppa_staff_roles sr on sr.staff_id=s.id join public.oppa_role_permissions rp on rp.role_id=sr.role_id join public.oppa_permissions p on p.id=rp.permission_id where s.user_id=$1 and s.status='active' order by p.code`,[req.auth.userId]);
  res.json({permissions:q.rows.map(x=>x.code)});
 }catch(e){next(e)}});
 return r;
}