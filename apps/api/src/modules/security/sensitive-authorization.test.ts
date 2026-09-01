import { describe, expect, it, vi } from "vitest";
import { DefaultSensitiveAuthorization } from "./default-sensitive-authorization.js";
describe("DefaultSensitiveAuthorization",()=>{
 it("fails closed when device proof fails",async()=>{
  const proofs={verify:vi.fn().mockRejectedValue(new Error("DEVICE_PROOF_INVALID"))};
  const auth=new DefaultSensitiveAuthorization(proofs as any);
  await expect(auth.authorize({userId:"u1",operation:"wallet_transfer",proof:{deviceId:"d1",challenge:"c",signature:"s"}})).rejects.toThrow("DEVICE_PROOF_INVALID");
 });
 it("allows only after device proof succeeds",async()=>{
  const proofs={verify:vi.fn().mockResolvedValue(true)};
  const auth=new DefaultSensitiveAuthorization(proofs as any);
  await expect(auth.authorize({userId:"u1",operation:"payment_reversal",proof:{deviceId:"d1",challenge:"c",signature:"s"}})).resolves.toBe(true);
  expect(proofs.verify).toHaveBeenCalledWith("u1","payment_reversal",{deviceId:"d1",challenge:"c",signature:"s"});
 });
});
