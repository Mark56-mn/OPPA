import { describe, expect, it } from "vitest";
import { SecurityService } from "./security-service.js";
function repo(){
 let record:any=null, attempts=0, consumed=false;
 return {
  createChallenge:async(i:any)=>{record={id:"c1",userId:i.userId,deviceId:i.deviceId??null,purpose:i.purpose,challengeHash:i.challengeHash};},
  findActiveChallenge:async()=>record,
  incrementChallengeAttempt:async()=>{attempts++;},
  consumeChallenge:async()=>{if(consumed)return false;consumed=true;return true;},
  recordEvent:async()=>{}
 };
}
describe("SecurityService",()=>{
 it("creates a short-lived opaque step-up challenge",async()=>{
  const s=new SecurityService(repo() as any); const r=await s.createStepUp("u1","wallet_transfer");
  expect(r.challenge).toHaveLength(43); expect(new Date(r.expiresAt).getTime()).toBeGreaterThan(Date.now());
 });
 it("rejects an invalid challenge without consuming it",async()=>{
  const s=new SecurityService(repo() as any); await s.createStepUp("u1","wallet_transfer");
  await expect(s.consumeStepUp("u1","wrong","wallet_transfer")).rejects.toThrow("STEP_UP_INVALID");
 });
 it("consumes a valid challenge once",async()=>{
  const s=new SecurityService(repo() as any); const r=await s.createStepUp("u1","wallet_transfer");
  await expect(s.consumeStepUp("u1",r.challenge,"wallet_transfer")).resolves.toBe(true);
 });
});
