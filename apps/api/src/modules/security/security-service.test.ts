import assert from "node:assert/strict";
import test from "node:test";
import { SecurityService } from "./security-service.js";
import { hashIntent } from "./intent-binding.js";
function repo(){
 let record:any=null, attempts=0, consumed=false, events:any[]=[];
 return {
  events,
  isActiveDevice:async()=>true,
  createChallenge:async(i:any)=>{record={id:"c1",userId:i.userId,deviceId:i.deviceId??null,purpose:i.purpose,challengeHash:i.challengeHash,intentHash:i.intentHash??null};},
  findActiveChallenge:async()=>record,
  incrementChallengeAttempt:async()=>{attempts++;},
  consumeChallenge:async()=>{if(consumed)return false;consumed=true;return true;},
  recordEvent:async(i:any)=>{events.push(i);}
 };
}
test("creates a short-lived opaque step-up challenge",async()=>{
  const s=new SecurityService(repo() as any); const r=await s.createStepUp("u1","wallet_transfer","d1");
  assert.equal(r.challenge.length,43); assert.ok(new Date(r.expiresAt).getTime()>Date.now());
});
test("binds the challenge to the operation intent",async()=>{
  const r=repo(); const s=new SecurityService(r as any);
  const intent={toUserId:"u2",amountMinor:50000,currency:"NGN",reference:"ref-1"};
  await s.createStepUp("u1","wallet_transfer","d1",intent);
  assert.equal(r.events[0].metadata.intentBound,true);
  assert.deepEqual(r.events[0].metadata.intent,intent);
});
test("refuses to issue a challenge for an inactive device",async()=>{
  const security=repo() as any;
  security.isActiveDevice=async()=>false;
  await assert.rejects(new SecurityService(security).createStepUp("u1","wallet_transfer","d1"),{message:"DEVICE_NOT_ACTIVE"});
});
test("rejects an invalid challenge without consuming it and records a failure event",async()=>{
  const r=repo(); const s=new SecurityService(r as any); await s.createStepUp("u1","wallet_transfer","d1");
  await assert.rejects(s.consumeStepUp("u1","wrong","wallet_transfer"),{message:"STEP_UP_INVALID"});
  assert.equal(r.events.some((e:any)=>e.eventType==="security.step_up_failed"&&e.metadata.reason==="challenge_invalid"),true);
});
test("consumes a valid challenge once",async()=>{
  const s=new SecurityService(repo() as any); const r=await s.createStepUp("u1","wallet_transfer","d1");
  assert.equal(await s.consumeStepUp("u1",r.challenge,"wallet_transfer"),true);
});
test("records a failure event when no active challenge exists",async()=>{
  const r=repo(); (r as any).record=null; const s=new SecurityService(r as any);
  await assert.rejects(s.consumeStepUp("u1","anything","wallet_transfer"),{message:"STEP_UP_INVALID"});
  assert.equal(r.events.some((e:any)=>e.eventType==="security.step_up_failed"&&e.metadata.reason==="challenge_not_found"),true);
});
test("requires the intent bound to the challenge to be supplied on consumption",async()=>{
  const r=repo(); const s=new SecurityService(r as any);
  const intent={toUserId:"u2",amountMinor:50000,currency:"NGN",reference:"ref-1"};
  const created=await s.createStepUp("u1","wallet_transfer","d1",intent);
  await assert.rejects(s.consumeStepUp("u1",created.challenge,"wallet_transfer"),{message:"STEP_UP_INVALID"});
  assert.equal(r.events.some((e:any)=>e.eventType==="security.step_up_failed"&&e.metadata.reason==="intent_mismatch"),true);
});
test("rejects consumption when the supplied intent differs from the bound intent",async()=>{
  const r=repo(); const s=new SecurityService(r as any);
  const created=await s.createStepUp("u1","wallet_transfer","d1",{toUserId:"u2",amountMinor:50000,currency:"NGN",reference:"ref-1"});
  await assert.rejects(s.consumeStepUp("u1",created.challenge,"wallet_transfer",{toUserId:"u3",amountMinor:1,currency:"NGN",reference:"ref-2"}),{message:"STEP_UP_INVALID"});
  assert.equal(r.events.some((e:any)=>e.eventType==="security.step_up_failed"&&e.metadata.reason==="intent_mismatch"),true);
});
test("consumes a challenge when the exact bound intent is supplied",async()=>{
  const s=new SecurityService(repo() as any);
  const intent={toUserId:"u2",amountMinor:50000,currency:"NGN",reference:"ref-1"};
  const created=await s.createStepUp("u1","wallet_transfer","d1",intent);
  assert.equal(await s.consumeStepUp("u1",created.challenge,"wallet_transfer",intent),true);
});
test("rejects a non-object intent",async()=>{
  const s=new SecurityService(repo() as any);
  await assert.rejects(s.createStepUp("u1","wallet_transfer","d1","not-an-object" as any),{message:"INTENT_INVALID"});
});
test("intent hashing is stable regardless of key order",async()=>{
  const a=hashIntent({toUserId:"u2",amountMinor:50000,currency:"NGN",reference:"ref-1"});
  const b=hashIntent({reference:"ref-1",currency:"NGN",amountMinor:50000,toUserId:"u2"});
  assert.equal(a,b);
});