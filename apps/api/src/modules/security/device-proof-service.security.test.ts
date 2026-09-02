import assert from "node:assert/strict";
import { createHash, generateKeyPairSync, createSign } from "node:crypto";
import test from "node:test";
import { DeviceProofService } from "./device-proof-service.js";
function setup(){
 const {publicKey,privateKey}=generateKeyPairSync("ec",{namedCurve:"prime256v1"});
 const {privateKey:otherPrivateKey}=generateKeyPairSync("ec",{namedCurve:"prime256v1"});
 const calls:string[]=[];
 const repo:any={findActiveChallenge:async()=>({id:"c1",userId:"u1",deviceId:"d1",purpose:"wallet_transfer",challengeHash:hash("abc")}),getActiveDevicePublicKey:async()=>publicKey,consumeChallenge:async()=>true,incrementChallengeAttempt:async(id:string)=>{calls.push(`attempt:${id}`)},recordEvent:async(input:any)=>{calls.push(`event:${input.metadata.reason??"verified"}`)}};
 return {repo,privateKey,otherPrivateKey,calls};
}
function sign(key:any,value:string){const s=createSign("SHA256");s.update(value);s.end();return s.sign(key).toString("base64url")}
function hash(value:string){return createHash("sha256").update(value).digest("hex")}
test("accepts a valid device signature",async()=>{const {repo,privateKey,calls}=setup();assert.equal(await new DeviceProofService(repo).verify("u1","wallet_transfer",{deviceId:"d1",challenge:"abc",signature:sign(privateKey,"abc")}),true);assert.deepEqual(calls,["event:verified"])});
test("rejects an invalid signature and consumes an attempt",async()=>{const {repo,otherPrivateKey,calls}=setup();await assert.rejects(new DeviceProofService(repo).verify("u1","wallet_transfer",{deviceId:"d1",challenge:"abc",signature:sign(otherPrivateKey,"abc")}),{message:"DEVICE_PROOF_INVALID"});assert.deepEqual(calls,["attempt:c1","event:signature_invalid"])});
test("rejects a proof from a different device",async()=>{const {repo,privateKey}=setup();repo.findActiveChallenge=async()=>({id:"c1",userId:"u1",deviceId:"d2",purpose:"wallet_transfer",challengeHash:"x"});await assert.rejects(new DeviceProofService(repo).verify("u1","wallet_transfer",{deviceId:"d1",challenge:"abc",signature:sign(privateKey,"abc")}),{message:"DEVICE_PROOF_INVALID"})});
test("rejects a revoked device key and consumes an attempt",async()=>{const {repo,privateKey,calls}=setup();repo.getActiveDevicePublicKey=async()=>null;await assert.rejects(new DeviceProofService(repo).verify("u1","wallet_transfer",{deviceId:"d1",challenge:"abc",signature:sign(privateKey,"abc")}),{message:"DEVICE_PROOF_INVALID"});assert.deepEqual(calls,["attempt:c1","event:device_key_unavailable"])});
