import express from "express";
import helmet from "helmet";
import { errorHandler } from "./http/error-handler.js";
import { requestId } from "./http/request-id.js";
import { createRequireAuth } from "./http/auth-middleware.js";
import { db } from "./db/pool.js";
import { env, requiredEnv } from "./config/env.js";
import { createAuthRouter } from "./modules/auth/auth-routes.js";
import { AuthService } from "./modules/auth/auth-service.js";
import { PostgresIdentityRepository } from "./modules/identity/postgres-identity-repository.js";
import { PostgresOtpRepository } from "./modules/otp/postgres-otp-repository.js";
import { OtpService } from "./modules/otp/otp-service.js";
import { BulkSmsProvider } from "./modules/sms/bulksms-provider.js";
import { PostgresSessionRepository } from "./modules/session/postgres-session-repository.js";
import { SessionService } from "./modules/session/session-service.js";
import { DeviceService } from "./modules/device/device-service.js";
import { PostgresDeviceRepository } from "./modules/device/postgres-device-repository.js";
import { PostgresProfileRepository } from "./modules/profile/postgres-profile-repository.js";
import { createProfileRouter } from "./modules/profile/profile-routes.js";
import { PostgresConversationRepository } from "./modules/messaging/postgres-conversation-repository.js";
import { createConversationRouter } from "./modules/messaging/conversation-routes.js";
import { PostgresMessageRepository } from "./modules/messaging/postgres-message-repository.js";
import { createMessagingRouter } from "./modules/messaging/messaging-routes.js";
import { PostgresContactRepository } from "./modules/contact/postgres-contact-repository.js";
import { createContactRouter } from "./modules/contact/contact-routes.js";
import { PostgresWalletRepository } from "./modules/wallet/postgres-wallet-repository.js";
import { createWalletRouter } from "./modules/wallet/wallet-routes.js";
import { PostgresWalletTransferRepository } from "./modules/wallet/postgres-wallet-transfer-repository.js";
import { PaystackProvider } from "./modules/payments/paystack-provider.js";
import { FlutterwaveProvider } from "./modules/payments/flutterwave-provider.js";
import { PostgresPaymentRepository } from "./modules/payments/postgres-payment-repository.js";
import { PaymentService } from "./modules/payments/payment-service.js";
import { createPaymentRouter } from "./modules/payments/payment-routes.js";
import { createPaymentWebhookRouter } from "./modules/payments/payment-webhook-routes.js";
import { SecurityService } from "./modules/security/security-service.js";
import { PostgresSecurityProofRepository } from "./modules/security/postgres-security-proof-repository.js";
import { DeviceProofService } from "./modules/security/device-proof-service.js";
import { DefaultSensitiveAuthorization } from "./modules/security/default-sensitive-authorization.js";
import { createSecurityRouter } from "./modules/security/security-routes.js";

const app = express();
const port = env.port;
app.disable("x-powered-by");
app.use(helmet());
app.use(requestId);
app.use(express.json({ limit: "32kb", verify: (req, _res, buf) => { (req as any).rawBody = Buffer.from(buf); } }));

app.get("/health", (_req, res) => res.status(200).json({ ok: true, service: "oppa-api", timestamp: new Date().toISOString() }));
app.get("/readiness", async (_req, res, next) => {
  try {
    if (!db) return res.status(503).json({ ready: false, service: "oppa-api", reason: "DATABASE_NOT_CONFIGURED" });
    await db.query("select 1");
    res.status(200).json({ ready: true, service: "oppa-api" });
  } catch (e) { next(e); }
});

const authConfig = [env.otpPepper, env.refreshTokenPepper, env.accessTokenSecret];
if (env.nodeEnv === "production" && authConfig.some(v => !v)) throw new Error("Authentication secrets are not fully configured");

if (authConfig.every(Boolean)) {
  const sessionRepository = new PostgresSessionRepository();
  const devices = new DeviceService(new PostgresDeviceRepository());
  const otp = new OtpService(new PostgresOtpRepository(), new BulkSmsProvider(), requiredEnv("OPPA_OTP_PEPPER"), env.bulkSmsSenderId, env.bulkSmsCallbackUrl);
  const sessions = new SessionService(sessionRepository, requiredEnv("OPPA_REFRESH_TOKEN_PEPPER"), requiredEnv("OPPA_ACCESS_TOKEN_SECRET"));
  const auth = new AuthService(otp, new PostgresIdentityRepository(), sessions, devices);

  app.use("/v1/auth", createAuthRouter(auth));
  const protectedRouter = express.Router();
  protectedRouter.use(createRequireAuth(requiredEnv("OPPA_ACCESS_TOKEN_SECRET"), sessionRepository));

  const securityRepository = new PostgresSecurityProofRepository();
  const security = new SecurityService(securityRepository);
  const deviceProofs = new DeviceProofService(securityRepository);
  const sensitiveAuthorization = new DefaultSensitiveAuthorization(deviceProofs);

  protectedRouter.use("/security", createSecurityRouter(security));
  protectedRouter.use("/profile", createProfileRouter(new PostgresProfileRepository()));
  protectedRouter.use("/contacts", createContactRouter(new PostgresContactRepository()));
  protectedRouter.use("/conversations", createConversationRouter(new PostgresConversationRepository()));
  protectedRouter.use("/", createMessagingRouter(new PostgresMessageRepository()));
  protectedRouter.use("/wallet", createWalletRouter(new PostgresWalletRepository(), new PostgresWalletTransferRepository(), sensitiveAuthorization));

  const providers:any = {};
  if (env.paystackSecret) providers.paystack = new PaystackProvider(env.paystackSecret);
  if (env.flutterwaveSecret && env.flutterwaveWebhookSecret) providers.flutterwave = new FlutterwaveProvider(env.flutterwaveSecret, env.flutterwaveWebhookSecret);
  const payments = new PaymentService(new PostgresPaymentRepository(), providers, sensitiveAuthorization);
  protectedRouter.use("/payments", createPaymentRouter(payments));
  app.use("/v1/payments/webhooks", createPaymentWebhookRouter(payments));
  app.use("/v1", protectedRouter);
}

app.use((_req, res) => res.status(404).json({ error: "NOT_FOUND", requestId: res.locals.requestId }));
app.use(errorHandler);
app.listen(port, () => console.log(`OPPA API listening on port ${port}`));
