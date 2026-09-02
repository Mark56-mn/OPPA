import assert from "node:assert/strict";
import test from "node:test";
import { SecurityService } from "./security-service.js";
function repo(){
 let record:any=null, attempts=0, consumed=false;
 return {
  isActiveDevice:async()=>true,
  createChallenge:async(i:any)=>{record={id:"c1",userId:i.userId,deviceId:i.deviceId??null,purpose:i.purpose,challengeHash:i.challengeHash};},
  findActiveChallenge:async()=>record,
  incrementChallengeAttempt:async()=>{attempts++;},
  consumeChallenge:async()=>{if(consumed)return false;consumed=true;return true;},
  recordEvent:async()=>{}
 };
}
test("creates a short-lived opaque step-up challenge",async()=>{
  const s=new SecurityService(repo() as any); const r=await s.createStepUp("u1","wallet_transfer","d1");
  assert.equal(r.challenge.length,43); assert.ok(new Date(r.expiresAt).getTime()>Date.now());
});
test("refuses to issue a challenge for an inactive device",async()=>{
  const security=repo() as any;
  security.isActiveDevice=async()=>false;
  await assert.rejects(new SecurityService(security).createStepUp("u1","wallet_transfer","d1"),{message:"DEVICE_NOT_ACTIVE"});
});
test("rejects an invalid challenge without consuming it",async()=>{
  const s=new SecurityService(repo() as any); await s.createStepUp("u1","wallet_transfer","d1");
  await assert.rejects(s.consumeStepUp("u1","wrong","wallet_transfer"),{message:"STEP_UP_INVALID"});
});
test("consumes a valid challenge once",async()=>{
  const s=new SecurityService(repo() as any); const r=await s.createStepUp("u1","wallet_transfer","d1");
  assert.equal(await s.consumeStepUp("u1",r.challenge,"wallet_transfer"),true);
});
