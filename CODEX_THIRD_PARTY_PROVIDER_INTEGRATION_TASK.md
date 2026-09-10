# OPPA — THIRD-PARTY PROVIDER INTEGRATION TASK

Use this task from the current repository HEAD.

## Goal

Finish the real third-party provider layer before production credentials are added to Render.

Providers:
- BulkSMS Nigeria
- Termii
- Paystack
- Flutterwave V3

Do not merely add environment variables. Inspect the existing implementation and wire the providers into the real OPPA application with adapters, verification, webhooks, idempotency, retries/failure handling, security, and tests.

Never print, commit, log, or expose secrets. Provider secrets stay backend-only.

## 1. SMS / OTP

### BulkSMS Nigeria

Complete and verify production API integration, OTP delivery, sender ID, delivery callbacks/reports, provider request/message IDs, delivery-state persistence, timeout handling, safe retry policy, failure classification, rate limiting, OTP expiry/hash/attempt limits/replay prevention, and audit events.

Use these canonical names:

```text
BULKSMS_BASE_URL
BULKSMS_API_TOKEN
BULKSMS_SENDER_ID
BULKSMS_CALLBACK_URL
```

### Termii

Add Termii as a real second provider behind the same SMS abstraction. Inspect current official Termii documentation and use the account-specific base URL; do not blindly hard-code a regional endpoint.

Use these canonical names:

```text
TERMII_BASE_URL
TERMII_API_KEY
TERMII_SENDER_ID
TERMII_CALLBACK_URL
TERMII_WEBHOOK_SECRET
```

Only require callback/webhook variables when the implemented Termii event flow actually uses them.

The authentication service should only know a normalized operation such as `sendOtp(phone, code)`. It must not care whether BulkSMS or Termii delivered the OTP.

Implement configurable primary/fallback provider behavior. Keep one OPPA OTP challenge across provider failover. Do not generate a second OTP merely because provider selection changes. Do not blindly send the same SMS twice after an ambiguous timeout. Record provider attempt/request IDs and prevent duplicate delivery caused by unsafe retries.

## 2. Paystack

Complete the real flow:

```text
Initialize
  ↓
Safe client information/access code
  ↓
Customer checkout
  ↓
Paystack webhook
  ↓
Verify webhook authenticity
  ↓
Server-side transaction verification
  ↓
Validate amount/currency/reference/user
  ↓
Idempotency/replay protection
  ↓
OPPA financial settlement
  ↓
Ledger + audit + risk
```

Canonical names:

```text
PAYSTACK_SECRET_KEY
PAYSTACK_PUBLIC_KEY
```

Do not create a separate Paystack webhook secret unless the actual implementation requires it. Follow Paystack's documented signature mechanism. Secret key is backend-only. Public key may be used client-side only where the SDK requires it.

Test duplicate webhooks/references, amount or currency mismatch, wrong user, failed/pending/abandoned transaction, forged webhook, provider verification failure, timeout/retry, and duplicate settlement. Never mutate wallet balance just because a client says payment succeeded.

## 3. Flutterwave V3

Use Flutterwave V3 as requested. Do not silently migrate this implementation to V4/OAuth.

Canonical names:

```text
FLUTTERWAVE_SECRET_KEY
FLUTTERWAVE_PUBLIC_KEY
FLUTTERWAVE_ENCRYPTION_KEY
FLUTTERWAVE_WEBHOOK_SECRET
```

Use the encryption key only for V3 endpoints that require it.

Complete initialization, customer checkout, webhook authentication/hash verification, server-side transaction verification, reference/user/amount/currency validation, idempotency/replay protection, OPPA settlement, ledger, audit and risk handling.

Secret and encryption keys are backend-only.

## 4. Provider abstraction

Inspect the existing architecture and keep provider-specific HTTP code inside adapters. Core OPPA code should depend on normalized provider interfaces/results.

Normalize states such as accepted, pending, successful, failed, reversed, and unknown/ambiguous. Unknown must never become success.

## 5. Webhook security

Every payment webhook must verify authenticity before state mutation, use the raw request body where required, reject invalid signatures, be idempotent, tolerate duplicate delivery, not trust client callback data as authoritative, verify provider transaction state where appropriate, validate amount/currency/reference, create audit events, and never double-credit a wallet.

SMS callbacks/events must also be validated according to provider capabilities.

## 6. Wallet/ledger boundary

External providers must never directly expose arbitrary wallet-balance mutations.

Correct model:

```text
Provider event
 ↓
Verify provider
 ↓
Identify OPPA transaction
 ↓
Validate expected state
 ↓
Idempotency check
 ↓
Financial DB transaction
 ↓
Double-entry ledger
 ↓
Audit event
```

Preserve all existing database constraints, authorization, transaction locking, RLS, and wallet invariants.

## 7. Retry and ambiguity rules

Use endpoint-aware retries. Do not blindly retry payment-creating requests when the original request may already have succeeded. Use persisted provider reference, OPPA transaction reference, idempotency key, and transaction state to resolve ambiguity.

## 8. Configuration

Update `apps/api/src/config/env.ts`, `.env.example`, relevant deployment/configuration documentation, and configuration tests. Keep working existing names where possible. Configuration validation must report only variable names, never values.

## 9. Testing

Add/repair tests for SMS provider success/fallback/timeout/duplicate prevention/OTP expiry/reuse/attempt limits; Paystack initialization/webhook authentication/replay/success/mismatch/verification failure/duplicate settlement; Flutterwave V3 initialization/webhook authentication/replay/success/mismatch/verification failure/duplicate settlement; and cross-provider outage/timeout/malformed response/unknown status/retry/idempotency/no secret leakage.

Use mocks for deterministic tests. If real credentials are available in the agent environment, run separate integration checks without exposing credentials.

## 10. Render secret names

The owner will add generated credentials to Render.

```text
DATABASE_URL

OPPA_ACCESS_TOKEN_SECRET
OPPA_REFRESH_TOKEN_PEPPER
OPPA_OTP_PEPPER

BULKSMS_BASE_URL
BULKSMS_API_TOKEN
BULKSMS_SENDER_ID
BULKSMS_CALLBACK_URL

TERMII_BASE_URL
TERMII_API_KEY
TERMII_SENDER_ID
TERMII_CALLBACK_URL
TERMII_WEBHOOK_SECRET

PAYSTACK_SECRET_KEY
PAYSTACK_PUBLIC_KEY

FLUTTERWAVE_SECRET_KEY
FLUTTERWAVE_PUBLIC_KEY
FLUTTERWAVE_ENCRYPTION_KEY
FLUTTERWAVE_WEBHOOK_SECRET
```

Do not require optional provider secrets when the feature is intentionally disabled.

## 11. Live verification

If credentials are available in the agent environment, verify provider authentication, reachability, sender ID where possible, test/live mode alignment, Termii account base URL, and webhook configuration where possible. Never print credential values. If credentials are unavailable, mark live verification BLOCKED rather than faking success.

## 12. Webhooks

Inspect the actual source routes and document exact deployed webhook URLs after confirming them. Use the real API hostname; do not invent routes. Expected host shape is `https://api.oppa-technologies.online/...`.

## 13. Security gate

Before declaring complete: no secrets in Git/frontend/logs/errors, no plaintext OTP logs, webhook verification enforced, server-side payment verification enforced, idempotency enforced, amount/currency/user ownership validated, unknown provider state never treated as success, provider failures cannot corrupt wallet state, existing database/ledger boundaries preserved, and audit events exist for sensitive provider/financial transitions.

## 14. Do not stop at configuration

Continue through provider architecture, Termii, BulkSMS hardening, Paystack, Flutterwave V3, webhooks, retries/idempotency, wallet/ledger integration, configuration/docs, tests, TypeScript checks, Flutter checks, available integration checks, adversarial review, commit, and `CODEX_HANDOFF.md` update.

Do not stop merely because environment variables were added.

## 15. Handoff

Update `CODEX_HANDOFF.md` with commit SHA, files changed, provider integrations completed, exact test results, live checks completed, blocked checks, required Render secrets, exact webhook URLs, provider-dashboard actions still required, known risks, and next action.

If credits/time run out, record completed, partial, blocked, and not-started work before stopping.

## Owner credential checklist

Generate fresh credentials and add them to Render using the exact names above. For Flutterwave, use the requested V3 credentials. For Paystack, keep public and secret keys separate. For BulkSMS and Termii, keep API credentials server-side. Never paste secret values into GitHub, this task file, or ordinary chat.
