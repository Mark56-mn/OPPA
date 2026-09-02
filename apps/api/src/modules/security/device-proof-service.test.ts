import { describe, expect, it, vi } from "vitest";
import { generateKeyPairSync, createSign } from "node:crypto";
import { DeviceProofService } from "./device-proof-service.js";
function setup(){
 const {publicKey,privateKey}=generateKeyPairSync("ec",{namedCurve:"prime256v1"});
 const repo:any={findActiveChallenge:vi.fn().mockResolvedValue({id:"c1",userId:"u1",deviceId:"d1",purpose:"wallet_transfer",challengeHash:"x"}),getActiveDevicePublicKey:vi.fn().mockResolvedValue(publicKey),consumeStepUp:vi.fn().mockResolvedValue(true),incrementChallengeAttempt:vi.fn()};
 return {repo,privateKey};
}
function sign(key:any,value:string){const s=createSign("SHA256");s.update(value);s.end();return s.sign(key).toString("base64url")}
describe("DeviceProofService",()=>{
 it("accepts a valid signature",async()=>{const {repo,privateKey}=setup();const s=new DeviceProofService(repo);await expect(s.verify("u1","wallet_transfer",{deviceId:"d1",challenge:"abc",signature:sign(privateKey,"abc")})).resolves.toBe(true);expect(repo.consumeStepUp).toHaveBeenCalled()});
 it("rejects a wrong signature",async()=>{const {repo,privateKey}=setup();const s=new DeviceProofService(repo);await expect(s.verify("u1","wallet_transfer",{deviceId:"d1",challenge:"abc",signature:sign(privateKey,"wrong")})).rejects.toThrow("DEVICE_PROOF_INVALID");});
 it("rejects a different device",async()=>{const {repo,privateKey}=setup();repo.findActiveChallenge.mockResolvedValue({...await repo.findActiveChallenge(),deviceId:"d2"});const s=new DeviceProofService(repo);await expect(s.verify("u1","wallet_transfer",{deviceId:"d1",challenge:"abc",signature:sign(privateKey,"abc")})).rejects.toThrow("DEVICE_PROOF_INVALID");});
});
