import { db } from "../../db/pool.js";
export async function hasPermission(userId:string, permission:string):Promise<boolean>{
 if(!db) throw new Error("DATABASE_URL is not configured");
 const r=await db.query(`select exists(
   select 1 from public.oppa_staff s
   join public.oppa_staff_roles sr on sr.staff_id=s.id
   join public.oppa_role_permissions rp on rp.role_id=sr.role_id
   join public.oppa_permissions p on p.id=rp.permission_id
   where s.user_id=$1 and s.status='active' and p.code=$2
 ) as allowed`,[userId,permission]);
 return Boolean(r.rows[0]?.allowed);
}
export function requirePermission(permission:string){
 return async (req:any,res:any,next:any)=>{
  try{if(!req.auth?.userId)return res.status(401).json({error:"UNAUTHORIZED",requestId:res.locals.requestId});
   if(!(await hasPermission(req.auth.userId,permission)))return res.status(403).json({error:"FORBIDDEN",requestId:res.locals.requestId});
   next();
  }catch(e){next(e)}
 };
}