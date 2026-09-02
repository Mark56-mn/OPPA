import assert from "node:assert/strict";
import test from "node:test";
import { DefaultSensitiveAuthorization } from "./default-sensitive-authorization.js";
test("fails closed when device proof fails",async()=>{
  const proofs={verify:async()=>{throw new Error("DEVICE_PROOF_INVALID")}};
  const auth=new DefaultSensitiveAuthorization(proofs as any);
  await assert.rejects(auth.authorize({userId:"u1",operation:"wallet_transfer",proof:{deviceId:"d1",challenge:"c",signature:"s"}}),{message:"DEVICE_PROOF_INVALID"});
});
test("allows only after device proof succeeds",async()=>{
  let received:unknown;
  const proofs={verify:async(...args:unknown[])=>{received=args;return true}};
  const auth=new DefaultSensitiveAuthorization(proofs as any);
  assert.equal(await auth.authorize({userId:"u1",operation:"payment_reversal",proof:{deviceId:"d1",challenge:"c",signature:"s"}}),true);
  assert.deepEqual(received,["u1","payment_reversal",{deviceId:"d1",challenge:"c",signature:"s"}]);
});
