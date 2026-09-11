# OPPA API

## Authentication

### POST /auth/otp/request

Request:
{ "phone": "+2348012345678" }

Response:
- 202 with `{ "challengeId": "...", "delivery": "submitted" | "unknown" }`
- 400 for invalid phone input
- 429 when an OTP is active or rate limits are exceeded
- 502 `SMS_DELIVERY_FAILED` when every configured SMS provider definitively rejected the send (no challenge lingers)
- 503 `SMS_GATEWAY_UNCONFIGURED` when no SMS provider credential is configured (fails closed; no fake delivery)

`delivery: "unknown"` means the send outcome is ambiguous (provider timeout/network error). An SMS may still be in flight, so the challenge stays verifiable and the client should proceed to the code-entry screen; the API never auto-resends on ambiguity (duplicate-delivery prevention). OTP requests are served through a configurable primary/fallback provider chain (BulkSMS Nigeria, Termii) behind one normalized `sendOtp(phone, code)` operation — provider failover never generates a second OTP.

### POST /auth/otp/verify

Request:
{ "phone": "+2348012345678", "code": "123456" }

Response:
- 200 after successful verification
- 401 for invalid, expired, or exhausted OTP attempts

The OTP itself is never returned by the API.

## Sensitive operations (step-up)

Wallet transfers and payment reversals require a device-bound proof that is cryptographically bound to the exact operation parameters (recipient, amount, currency, reference). The client must sign the challenge together with the canonicalized intent.

### POST /security/step-up/challenge

Creates a step-up challenge, optionally bound to an operation intent.

Request (intent-bound, e.g. wallet transfer):
```json
{
  "purpose": "wallet_transfer",
  "deviceId": "<device-id>",
  "intent": { "toUserId": "<user-id>", "amountMinor": 50000, "currency": "NGN", "reference": "ref-1" }
}
```

Response:
- 201 with `{ "challenge": "<opaque-value>", "expiresAt": "<iso>" }`
- 403 when the device is not active
- 409 when another challenge is being issued concurrently (`STEP_UP_CHALLENGE_CONFLICT`)
- 400 for an invalid intent (`INTENT_INVALID`, `INTENT_TOO_DEEP`, `INTENT_TOO_LARGE`)

Only one active challenge per user + purpose exists at a time; issuing a new challenge invalidates the previous one atomically.

### POST /wallet/transfer

Requires a proof whose signature covers `challenge + "." + canonicalJson(intent)` where `intent` is derived server-side from the request (`toUserId`, `amountMinor`, `currency`, `reference`). The challenge must have been created with the same intent.

Request:
```json
{
  "toUserId": "<user-id>",
  "amountMinor": 50000,
  "reference": "ref-1",
  "deviceId": "<device-id>",
  "challenge": "<opaque-value>",
  "signature": "<base64url-signature>"
}
```

Response:
- 201 on success
- 401 when the proof or intent does not validate
- 409 for insufficient funds / reused reference

### POST /payments/reverse

Reverses a settled payment the caller owns. Requires a proof bound to the payment's `paymentId`, `reference`, `amountMinor`, `currency`.

Request:
```json
{
  "paymentId": "<payment-id>",
  "reason": "duplicate charge",
  "deviceId": "<device-id>",
  "challenge": "<opaque-value>",
  "signature": "<base64url-signature>"
}
```

Response:
- 200 with the reversed payment record
- 401 when the proof or intent does not validate
- 404 when the payment does not exist or does not belong to the caller
- 409 when the payment is not settled or already reversed

Provider-initiated refund webhooks remain explicitly unimplemented (`501`) until provider refund APIs are integrated.

## Payment webhooks (unauthenticated surface)

Only two unauthenticated payment routes exist. Both verify authenticity before any state mutation, over the RAW request body:

- `POST /payments/webhooks/paystack` — HMAC-SHA512 hex of the raw body keyed with `PAYSTACK_SECRET_KEY` in `x-paystack-signature`.
- `POST /payments/webhooks/flutterwave` — Flutterwave V3 secret echoed verbatim in the `verif-hash` header, compared in constant time.

Settlement flow: verify signature → parse + extract reference → event gate (non-charge events are acknowledged without mutation) → **server-side verification against the provider API** (webhook data alone never settles) → resolve the OPPA transaction from our own database (ownership from the row, not the payload) → amount/currency/reference validation → idempotent settlement (row lock, single wallet credit, double-entry reference, audit event, outbox notification). Duplicates, replays, amount/currency mismatch, forged signatures and provider outages all fail closed and never double-credit a wallet.

## SMS delivery callbacks (unauthenticated surface)

- `POST /sms/webhooks/bulksms` — BulkSMS delivery reports (no provider signing exists): payload-validated, bounded to the delivery-attempt ledger; can never touch OTP challenges, wallets, or payments.
- `POST /sms/webhooks/termii` — Termii events, HMAC-verified with `TERMII_WEBHOOK_SECRET` in `x-termii-signature`; the flow is opt-in and disabled (401) when no secret is configured.

All attempts (accepted/failed/unknown) and terminal delivery states persist to the `oppa_sms_delivery_attempts` ledger (migration 0022) — auditable failover, durable per-challenge rate budget, and reconciliation support without storing any OTP material.

## Provider configuration introspection

`GET /config/providers` reports which provider variables are present — **names only, never values** — plus the SMS provider order and gateway mode (`live` | `unconfigured`).

## Wallet transfer limits

Wallet transfers are limited per user by default (single transfer, daily total, daily count) and enforced atomically with the transfer. Exceeding a limit returns `409 WALLET_TRANSFER_LIMIT_EXCEEDED`. An operator `block` decision on the `user` or `transfer` scope returns `409 WALLET_TRANSFER_BLOCKED`.

## Risk & Abuse (admin / fraud analyst)

All endpoints require staff authentication plus the `fraud.review` permission (seeded for the `fraud_analyst` role).

### GET /admin/risk/decisions?userId=&limit=

Lists operator risk decisions for a user, newest first.

### GET /admin/risk/events?userId=&limit=

Lists recorded risk events (OTP abuse, transfer velocity, payment anomalies) for a user.

### POST /admin/risk/decisions

Issues an operator decision that money-movement paths enforce server-side.

Request:
```json
{
  "userId": "<user-id>",
  "scope": "payment",
  "decision": "block",
  "reason": "chargeback pattern",
  "expiresAt": "2026-10-01T00:00:00Z"
}
```

Response:
- 201 when created
- 400 for invalid scope/decision/reason/expiry
- 403 without the `fraud.review` permission

A `block` on the `payment` scope stops payment settlement; `user`/`transfer` blocks stop wallet transfers. A `review` decision stops settlement but leaves transfers allowed.
