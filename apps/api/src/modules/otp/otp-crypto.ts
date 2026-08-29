import { createHash, randomInt } from "node:crypto";
import { otpPolicy } from "./otp-policy.js";

export function generateOtp(): string {
  const upper = 10 ** otpPolicy.digits;
  return randomInt(0, upper).toString().padStart(otpPolicy.digits, "0");
}

export function hashOtp(phone: string, otp: string, pepper: string): string {
  return createHash("sha256")
    .update(`${pepper}:${phone}:${otp}`)
    .digest("hex");
}
