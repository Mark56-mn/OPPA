import { createHash } from "node:crypto";
export type AuthorizationContextValue=string|number|boolean|null;
export type AuthorizationContext=Record<string,AuthorizationContextValue>;
function canonical(value:AuthorizationContext){const keys=Object.keys(value).sort();return JSON.stringify(Object.fromEntries(keys.map(k=>{const v=value[k];if(typeof v==="number"&&!Number.isFinite(v))throw Error("SENSITIVE_CONTEXT_INVALID");return [k,v]})))}
export function authorizationContextHash(operation:string,context:AuthorizationContext){if(!operation||operation.length>64)throw Error("SENSITIVE_CONTEXT_INVALID");return createHash("sha256").update(operation+"\n"+canonical(context),"utf8").digest("hex")}
export function authorizationSigningPayload(challenge:string,operation:string,context:AuthorizationContext){if(!challenge||challenge.length>128)throw Error("SENSITIVE_CONTEXT_INVALID");return challenge+"."+authorizationContextHash(operation,context)}
