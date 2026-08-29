export function requiredEnv(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

export const env = {
  port: Number(process.env.PORT ?? 8080),
  nodeEnv: process.env.NODE_ENV ?? "development",
  bulkSmsBaseUrl: process.env.BULKSMS_BASE_URL ?? "https://www.bulksmsnigeria.com/api/v2",
  bulkSmsApiToken: process.env.BULKSMS_API_TOKEN,
  bulkSmsSenderId: process.env.BULKSMS_SENDER_ID ?? "OPPA",
  bulkSmsCallbackUrl: process.env.BULKSMS_CALLBACK_URL,
  otpPepper: process.env.OPPA_OTP_PEPPER,
  refreshTokenPepper: process.env.OPPA_REFRESH_TOKEN_PEPPER,
  accessTokenSecret: process.env.OPPA_ACCESS_TOKEN_SECRET
};
