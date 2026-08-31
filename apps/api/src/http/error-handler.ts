import type { ErrorRequestHandler } from "express";
const statuses:Record<string,number>={FORBIDDEN:403,USER_NOT_FOUND:404,MESSAGE_BODY_REQUIRED:400,MESSAGE_TOO_LONG:413,OTP_INVALID_OR_EXPIRED:401,DEVICE_ID_INVALID:400,PROFILE_FIELD_INVALID:400,PROFILE_FIELD_TOO_LONG:400,CONVERSATION_SELF_INVALID:400,CONTACT_SELF_INVALID:400};
export const errorHandler:ErrorRequestHandler=(error,_req,res,_next)=>{
 console.error(error);if(res.headersSent)return;
 const code=typeof error?.message==="string"?error.message:"INTERNAL_SERVER_ERROR";
 res.status(statuses[code]??500).json({error:code,requestId:res.locals.requestId});
};