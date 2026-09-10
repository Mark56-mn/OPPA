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
import { FailoverSmsGateway } from "./modules/sms/sms-gateway.js";
import { PostgresSmsAttemptRepository } from "./modules/sms/postgres-sms-attempt-repository.js";
import { SmsDeliveryRecorder } from "./modules/sms/sms-delivery-recorder.js";
import { createSmsCallbackRouter } from "./modules/sms/sms-callback-routes.js";
import { describeConfig, smsProviderOrder } from "./config/env.js";
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
import { PaymentService } from "./modules/payments/payment-service.js";
import { PostgresPaymentRepository } from "./modules/payments/postgres-payment-repository.js";
import { createPaymentRouter } from "./modules/payments/payment-routes.js";
import { createPaymentWebhookRouter } from "./modules/payments/payment-webhook-routes.js";
import { SecurityService } from "./modules/security/security-service.js";
import { PostgresSecurityProofRepository } from "./modules/security/postgres-security-proof-repository.js";
import { DeviceProofService } from "./modules/security/device-proof-service.js";
import { DefaultSensitiveAuthorization } from "./modules/security/default-sensitive-authorization.js";
import { createSecurityRouter } from "./modules/security/security-routes.js";
import { createAdminRouter } from "./modules/admin/admin-routes.js";
import { createAdminEmergencyRouter } from "./modules/admin/admin-emergency-routes.js";
import { PostgresRiskRepository } from "./modules/risk/postgres-risk-repository.js";
import { RiskService } from "./modules/risk/risk-service.js";
import { createAccountRouter } from "./modules/account/account-routes.js";
import { PostgresSecurityEventRecorder } from "./modules/auth/postgres-security-event-recorder.js";
import { PostgresNotificationRepository } from "./modules/notifications/postgres-notification-repository.js";
import { NotificationService } from "./modules/notifications/notification-service.js";
import { createNotificationRouter } from "./modules/notifications/notification-routes.js";
import { createBusinessRouter } from "./modules/business/business-routes.js";
import { PostgresBusinessRepository } from "./modules/business/postgres-business-repository.js";
import { CallsService, PostgresCallsStore } from "./modules/calls/calls-service.js";
import { createCallsRouter } from "./modules/calls/calls-routes.js";

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
  const riskRepository = new PostgresRiskRepository();
  const risk = new RiskService(riskRepository);
  // SMS failover: BulkSMS primary, Termii fallback, per config order. Every
  // attempt is persisted; the OTP challenge is shared across provider failover.
  // With no provider configured the gateway fails closed (SMS_GATEWAY_UNCONFIGURED).
  const smsAttempts = new PostgresSmsAttemptRepository();
  const sms = FailoverSmsGateway.fromConfig(smsAttempts);
  const otp = new OtpService(
    new PostgresOtpRepository(),
    sms.gateway ?? new FailoverSmsGateway([], smsAttempts),
    requiredEnv("OPPA_OTP_PEPPER"),
    risk
  );
  const sessions = new SessionService(sessionRepository, requiredEnv("OPPA_REFRESH_TOKEN_PEPPER"), requiredEnv("OPPA_ACCESS_TOKEN_SECRET"));
  const auth = new AuthService(otp, new PostgresIdentityRepository(), sessions, devices, new PostgresSecurityEventRecorder());

  app.use("/v1/auth", createAuthRouter(auth));
  const protectedRouter = express.Router();
  protectedRouter.use(createRequireAuth(requiredEnv("OPPA_ACCESS_TOKEN_SECRET"), sessionRepository));

  protectedRouter.use("/account", createAccountRouter(sessions, devices, new PostgresSecurityEventRecorder()));

  const notificationRepository = new PostgresNotificationRepository();
  const notifications = new NotificationService(notificationRepository);
  protectedRouter.use("/notifications", createNotificationRouter(notifications, notificationRepository));
  // Background delivery worker: drains the durable outbox periodically without
  // keeping the event loop alive (unref) so tooling/tests can exit cleanly.
  const notificationWorker = setInterval(() => {
    notifications.processBatch(20).catch(() => {
      // Worker failures are durable in the outbox (attempts/last_error); the
      // next tick retries with backoff.
    });
  }, 60_000);
  notificationWorker.unref?.();

  const securityRepository = new PostgresSecurityProofRepository();
  const security = new SecurityService(securityRepository);
  const deviceProofs = new DeviceProofService(securityRepository);
  const sensitiveAuthorization = new DefaultSensitiveAuthorization(deviceProofs);

  protectedRouter.use("/security", createSecurityRouter(security));
  protectedRouter.use("/admin", createAdminRouter(riskRepository));
  protectedRouter.use("/admin", createAdminEmergencyRouter());
  protectedRouter.use("/profile", createProfileRouter(new PostgresProfileRepository()));
  protectedRouter.use("/contacts", createContactRouter(new PostgresContactRepository()));
  const messageRepository = new PostgresMessageRepository();
  protectedRouter.use("/conversations", createConversationRouter(new PostgresConversationRepository(), messageRepository));
  protectedRouter.use("/", createMessagingRouter(messageRepository));
  protectedRouter.use("/business", createBusinessRouter(new PostgresBusinessRepository()));

  // OPPA-native calls (Stage L): authenticated signaling over REST polling.
  const calls = new CallsService(new PostgresCallsStore());
  protectedRouter.use("/", createCallsRouter(calls));
  // Ring-timeout sweeper: expires stale ringing calls (missed-call semantics)
  // without keeping the event loop alive.
  const callSweeper = setInterval(() => {
    calls.sweepStale().catch(() => {});
  }, 30_000);
  callSweeper.unref?.();
  protectedRouter.use("/wallet", createWalletRouter(new PostgresWalletRepository(), new PostgresWalletTransferRepository(riskRepository), sensitiveAuthorization));

  const providers:any = {};
  if (env.paystackSecret) providers.paystack = new PaystackProvider(env.paystackSecret, { baseUrl: env.paystackBaseUrl });
  if (env.flutterwaveSecret && env.flutterwaveWebhookSecret) providers.flutterwave = new FlutterwaveProvider(env.flutterwaveSecret, env.flutterwaveWebhookSecret, { baseUrl: env.flutterwaveBaseUrl, encryptionKey: env.flutterwaveEncryptionKey });
  const paymentRepository = new PostgresPaymentRepository();
  const payments = new PaymentService(paymentRepository, providers, sensitiveAuthorization, risk);
  protectedRouter.use("/payments", createPaymentRouter(payments, paymentRepository));
  app.use("/v1/payments/webhooks", createPaymentWebhookRouter(payments));

  // SMS delivery callbacks (provider -> OPPA). Unauthenticated by design for
  // providers without signing; strictly validated and bounded to the DLR ledger.
  app.use("/v1/sms/webhooks", createSmsCallbackRouter(new SmsDeliveryRecorder(smsAttempts)));

  // Configuration introspection for deployment checks. Reports variable NAMES
  // and presence only — never values.
  app.get("/v1/config/providers", (_req, res) => {
    res.status(200).json({ providers: describeConfig(), sms: { order: smsProviderOrder(), mode: sms.mode } });
  });
  app.use("/v1", protectedRouter);
}

app.use((_req, res) => res.status(404).json({ error: "NOT_FOUND", requestId: res.locals.requestId }));
app.use(errorHandler);
app.listen(port, () => console.log(`OPPA API listening on port ${port}`));
