export const otpPolicy = {
  digits: 6,
  ttlSeconds: 300,
  maxVerificationAttempts: 5,
  requestCooldownSeconds: 60,
  maxRequestsPerHour: 5
} as const;
