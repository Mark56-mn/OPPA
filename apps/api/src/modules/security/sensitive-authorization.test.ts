import assert from "node:assert/strict";
import test from "node:test";
import { DefaultSensitiveAuthorization } from "./default-sensitive-authorization.js";
const context={fromUserId:"u1",toUserId:"u2",amountMinor:1000,currency:"NGN",reference:"r1"};
test("fails closed when device proof fails",async()=>{const proofs={verify:async()=>{throw new Error("DEVICE_PROOF_INVALID")}};const auth=new DefaultSensitiveAuthorization(proofs as any);await assert.rejects(auth.authorize({userId:"u1",operation:"wallet_transfer",proof:{deviceId:"d1",challenge:"c",signature:"s",context}}),{message:"DEVICE_PROOF_INVALID"})});
test("passes exact proof context to device verification",async()=>{let received:any;const proofs={verify:async(...args:any[])=>{received=args;return true}};const auth=new DefaultSensitiveAuthorization(proofs as any);assert.equal(await auth.authorize({userId:"u1",operation:"wallet_transfer",proof:{deviceId:"d1",challenge:"c",signature:"s",context}}),true);assert.deepEqual(received,["u1","wallet_transfer",{deviceId:"d1",challenge:"c",signature:"s",context}])});
