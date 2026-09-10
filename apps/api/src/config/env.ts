/**
 * Central environment configuration.
 *
 * Rules:
 * - Provider secrets are backend-only. Never log, echo, or serialize values here.
 * - `describeConfig()` reports ONLY variable names (present/absent) so support
 *   tooling can diagnose configuration without ever exposing a secret value.
 * - Keep existing variable names working; add new names additively.
 * - Optional provider features are disabled when their secrets are absent
 *   (e.g. Termii callbacks are only active when TERMII_WEBHOOK_SECRET is set).
 */

export function requiredEnv(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

function optionalEnv(name: string): string | undefined {
  const value = process.env[name]?.trim();
  return value ? value : undefined;
}

function positiveIntEnv(name: string, fallback: number): number {
  const raw = optionalEnv(name);
  if (!raw) return fallback;
  const parsed = Number(raw);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : fallback;
}

export const env = {
  port: Number(process.env.PORT ?? 8080),
  nodeEnv: process.env.NODE_ENV ?? "development",

  // --- Core auth secrets (Render: OPPA_*) ---
  otpPepper: process.env.OPPA_OTP_PEPPER,
  refreshTokenPepper: process.env.OPPA_REFRESH_TOKEN_PEPPER,
  accessTokenSecret: process.env.OPPA_ACCESS_TOKEN_SECRET,

  // --- BulkSMS Nigeria (https://www.bulksmsnigeria.com/api, API v2) ---
  bulkSmsBaseUrl: process.env.BULKSMS_BASE_URL ?? "https://www.bulksmsnigeria.com",
  bulkSmsApiToken: process.env.BULKSMS_API_TOKEN,
  bulkSmsSenderId: process.env.BULKSMS_SENDER_ID ?? "OPPA",
  bulkSmsCallbackUrl: process.env.BULKSMS_CALLBACK_URL,

  // --- Termii (account-specific base URL; do not hardcode a regional host) ---
  termiiBaseUrl: process.env.TERMII_BASE_URL,
  termiiApiKey: process.env.TERMII_API_KEY,
  termiiSenderId: process.env.TERMII_SENDER_ID ?? "OPPA",
  termiiCallbackUrl: process.env.TERMII_CALLBACK_URL,
  termiiWebhookSecret: process.env.TERMII_WEBHOOK_SECRET,

  // --- Paystack ---
  paystackSecret: process.env.PAYSTACK_SECRET_KEY,
  paystackPublicKey: process.env.PAYSTACK_PUBLIC_KEY,
  paystackBaseUrl: process.env.PAYSTACK_BASE_URL ?? "https://api.paystack.co",

  // --- Flutterwave V3 (V3 semantics; do not migrate to V4/OAuth) ---
  flutterwaveSecret: process.env.FLUTTERWAVE_SECRET_KEY,
  flutterwavePublicKey: process.env.FLUTTERWAVE_PUBLIC_KEY,
  flutterwaveEncryptionKey: process.env.FLUTTERWAVE_ENCRYPTION_KEY,
  flutterwaveWebhookSecret: process.env.FLUTTERWAVE_WEBHOOK_SECRET,
  flutterwaveBaseUrl: process.env.FLUTTERWAVE_BASE_URL ?? "https://api.flutterwave.com/v3",

  // --- SMS failover behavior ---
  // Order matters: first configured provider is primary, the rest are fallbacks.
  smsPrimaryProvider: process.env.SMS_PRIMARY_PROVIDER ?? "bulksms",
  smsSendTimeoutMs: positiveIntEnv("SMS_SEND_TIMEOUT_MS", 8_000),
  smsMaxAttemptsPerMinute: positiveIntEnv("SMS_MAX_ATTEMPTS_PER_MINUTE", 4)
} as const;

/**
 * Ordered SMS provider candidates by configured priority.
 * Unknown SMS_PRIMARY_PROVIDER values fall back to the default order.
 */
export function smsProviderOrder(): string[] {
  const primary = env.smsPrimaryProvider.trim().toLowerCase();
  const order = primary === "termii" ? ["termii", "bulksms"] : ["bulksms", "termii"];
  return order;
}

/**
 * Provider/feature configuration report. Returns NAMES and presence only —
 * never values — so it is safe to log or return to administrators.
 */
export function describeConfig(): Record<string, boolean> {
  return {
    BULKSMS_BASE_URL: Boolean(env.bulkSmsBaseUrl),
    BULKSMS_API_TOKEN: Boolean(env.bulkSmsApiToken),
    BULKSMS_SENDER_ID: Boolean(env.bulkSmsSenderId),
    BULKSMS_CALLBACK_URL: Boolean(env.bulkSmsCallbackUrl),
    TERMII_BASE_URL: Boolean(env.termiiBaseUrl),
    TERMII_API_KEY: Boolean(env.termiiApiKey),
    TERMII_SENDER_ID: Boolean(env.termiiSenderId),
    TERMII_CALLBACK_URL: Boolean(env.termiiCallbackUrl),
    TERMII_WEBHOOK_SECRET: Boolean(env.termiiWebhookSecret),
    PAYSTACK_SECRET_KEY: Boolean(env.paystackSecret),
    PAYSTACK_PUBLIC_KEY: Boolean(env.paystackPublicKey),
    FLUTTERWAVE_SECRET_KEY: Boolean(env.flutterwaveSecret),
    FLUTTERWAVE_PUBLIC_KEY: Boolean(env.flutterwavePublicKey),
    FLUTTERWAVE_ENCRYPTION_KEY: Boolean(env.flutterwaveEncryptionKey),
    FLUTTERWAVE_WEBHOOK_SECRET: Boolean(env.flutterwaveWebhookSecret),
    OPPA_ACCESS_TOKEN_SECRET: Boolean(env.accessTokenSecret),
    OPPA_REFRESH_TOKEN_PEPPER: Boolean(env.refreshTokenPepper),
    OPPA_OTP_PEPPER: Boolean(env.otpPepper)
  };
}
