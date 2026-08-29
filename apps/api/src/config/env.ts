export function requiredEnv(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

export const env = {
  port: Number(process.env.PORT ?? 8080),
  nodeEnv: process.env.NODE_ENV ?? "development",
  bulkSmsBaseUrl: process.env.BULKSMS_BASE_URL ?? "https://www.bulksmsnigeria.com",
  bulkSmsApiToken: process.env.BULKSMS_API_TOKEN
};
