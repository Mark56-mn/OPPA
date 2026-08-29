import { strict as assert } from "node:assert";
import test from "node:test";
import { generateOtp, hashOtp } from "./otp-crypto.js";

test("generates a six digit OTP", () => {
  const otp = generateOtp();
  assert.match(otp, /^\d{6}$/);
});

test("hashing is deterministic for the same inputs", () => {
  assert.equal(
    hashOtp("+2348012345678", "123456", "test-pepper"),
    hashOtp("+2348012345678", "123456", "test-pepper")
  );
});

test("hash changes when OTP changes", () => {
  assert.notEqual(
    hashOtp("+2348012345678", "123456", "test-pepper"),
    hashOtp("+2348012345678", "654321", "test-pepper")
  );
});
