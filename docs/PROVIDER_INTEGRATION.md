# OPPA Third-Party Provider Integration

This document is the deployment + operations reference for the provider layer.
The implementation lives in `apps/api/src/modules/{sms,payments}`; provider
HTTP code is confined to adapters, and core services depend only on normalized
interfaces (`SmsProvider`, `PaymentProvider`).

## Architecture

```
AuthService ──(normalized SmsProvider)──► FailoverSmsGateway ──► [BulkSMS | Termii] adapters
                                               │
                                               ├─ per-challenge attempt budget (durable)
                                               ├─ every attempt persisted (accepted/failed/unknown)
                                               └─ one OTP challenge across provider failover

PaymentService ──(normalized PaymentProvider)──► [Paystack | Flutterwave V3] adapters
        │
        └─ webhook router: raw-body signature verify → event gate → server-side
           verify → amount/currency/reference validation → idempotency → risk
           gates → single-transaction settlement (wallet + ledger + audit + outbox)
```

## SMS / OTP

### Providers

- **BulkSMS Nigeria** (API v2, `POST {BULKSMS_BASE_URL}/api/v2/sms`,
  `Authorization: Bearer`, `gateway: "otp"`, success = `status: "success"` +
  `data.message_id`). Delivery reports via `callback_url` on the send and
  `GET /api/v2/delivery-reports?message_id=...` for reconciliation.
- **Termii** (`POST {TERMII_BASE_URL}/api/sms/send`, `channel: "dnd"` for OTP
  per Termii guidance, success = HTTP 200 + `code: "ok"` + `message_id`).
  The base URL is the account-specific one shown in the Termii dashboard —
  never hardcode a regional host.

### Normalized outcomes

Every send attempt resolves to exactly one of:

- `accepted` — provider confirmed with a message id.
- `failed` — definitive rejection (HTTP error / provider error payload).
- `unknown` — timeout, network error, or ambiguous response (e.g. `ok`
  without message id). **Unknown is never treated as success** and never
  burns the OTP challenge: an SMS may still be in flight, and verification
  stays possible. Duplicate delivery is prevented by never re-sending on the
  same provider and by the durable per-challenge attempt budget
  (`SMS_MAX_ATTEMPTS_PER_MINUTE`).

Failover: primary → fallback happens on `failed` or `unknown` only. An
`accepted` from an earlier provider always stops the chain. The OTP code is
generated once; provider failover never generates a second OTP.

### Delivery callbacks

```
POST /v1/sms/webhooks/bulksms   # DLR; no provider HMAC exists — payload is
                                # validated and effects are bounded to the
                                # delivery ledger (never OTP/financial state)
POST /v1/sms/webhooks/termii    # HMAC-SHA512 of raw body in x-termii-signature
                                # (requires TERMII_WEBHOOK_SECRET; disabled 401 otherwise)
```

Effects are append-only observations (`dlr:delivered` / `dlr:failed` rows in
`oppa_sms_delivery_attempts`); intermediate/unknown statuses are ignored.
BulkSMS DLR vocabulary (`delivrd`, `sent awaiting status`, `undeliv`, ...)
and Termii event vocabulary (`Delivered`, `Failed`, `Message sent`, ...) are
mapped inside `sms-callback-routes.ts`; unknown strings stay `unknown`.

## Payments

### Paystack

- Webhook: `POST /v1/payments/webhooks/paystack`. Authenticity = HMAC-SHA512
  hex of the **raw** request body keyed with the **secret key**, in
  `x-paystack-signature` (Paystack's documented mechanism — there is no
  separate webhook secret, by design).
- Verify: `GET {PAYSTACK_BASE_URL}/transaction/verify/{reference}`
  server-side. Amounts arrive in minor units (kobo); no conversion.
- Status mapping: `success` → success, `ongoing` → pending,
  `abandoned` → abandoned, anything else → failed. Unknown never becomes
  success.

### Flutterwave V3 (deliberately V3, not V4/OAuth)

- Webhook: `POST /v1/payments/webhooks/flutterwave`. Authenticity = the
  webhook secret verbatim in the `verif-hash` header (constant-time compare).
- Verify: `GET {FLUTTERWAVE_BASE_URL}/transactions/verify_by_reference?tx_ref=...`
  server-side. Amounts arrive in major units; converted to kobo in the adapter.
- `FLUTTERWAVE_ENCRYPTION_KEY` is accepted for the V3 endpoints that require
  it; the initialize/verify surface does not use it and it is never logged.

### Settlement pipeline (identical for both providers)

1. Raw-body signature verification (constant-time; fail closed 401).
2. Strict reference shape validation.
3. Event-type gate: only `charge.success` (Paystack) / `charge.completed`,
   `payment.completed` (Flutterwave) may settle; other signed events are
   acknowledged with `{status: "ignored"}` and zero state mutation.
4. Server-side provider verification (webhook data alone never settles).
5. Reference/amount/currency agreement against our own recorded intent.
6. Ownership from our DB row (`oppa_payments.user_id`) — never from payload.
7. Idempotency: already-paid rows short-circuit; settlement is a single
   Postgres transaction with `for update` row lock, wallet credit,
   conflict-guarded ledger reference (`payment:{provider}:{reference}`),
   audit event, and notification outbox. Duplicate/replayed/racing webhooks
   credit exactly once.
8. Risk gates: operator block/review, then adaptive heuristics, both before
   any money moves.

`failed` → `paid` reconciliation is supported (a provider that reported
failure but later verifies successful settles once, provided no
`provider_transaction_id` was recorded). `reversed` can never settle.

## Configuration

All names are the canonical ones required by the task. `GET /v1/config/providers`
reports **only variable names and presence** (never values) plus the SMS
provider order and gateway mode — safe for deployment smoke checks. Optional
providers stay disabled when their secrets are absent; the SMS gateway fails
closed with `SMS_GATEWAY_UNCONFIGURED` when no SMS provider is configured.

Env template: `docs/provider-env.example` (kept out of the repo root so no
tooling auto-loads it).

## Render secret checklist (owner action)

```
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
TERMII_CALLBACK_URL          # only if Termii events are enabled
TERMII_WEBHOOK_SECRET        # only if Termii events are enabled

PAYSTACK_SECRET_KEY
PAYSTACK_PUBLIC_KEY          # client-side SDK use only

FLUTTERWAVE_SECRET_KEY
FLUTTERWAVE_PUBLIC_KEY
FLUTTERWAVE_ENCRYPTION_KEY
FLUTTERWAVE_WEBHOOK_SECRET
```

## Exact deployed webhook URLs

Configure these in each provider dashboard (host per the task: `api.oppa-technologies.online`):

| Provider    | Webhook URL                                                    | Dashboard location                  |
| ----------- | -------------------------------------------------------------- | ----------------------------------- |
| BulkSMS     | `https://api.oppa-technologies.online/v1/sms/webhooks/bulksms` | Sender/campaign DLR callback URL (also sent per-request via `BULKSMS_CALLBACK_URL`) |
| Termii      | `https://api.oppa-technologies.online/v1/sms/webhooks/termii`  | Settings → Webhook (enable events)  |
| Paystack    | `https://api.oppa-technologies.online/v1/payments/webhooks/paystack` | Settings → API Keys & Webhooks |
| Flutterwave | `https://api.oppa-technologies.online/v1/payments/webhooks/flutterwave` | Settings → Webhooks |

## Owner dashboard actions still required

1. Add the Render secrets above (fresh values; never paste them into chat/Git).
2. Register the four webhook URLs in the provider dashboards.
3. BulkSMS: confirm the `OPPA` sender ID is approved for the transactional
   route; Termii: confirm the account base URL and enable the DND route for
   the sender ID.
4. Paystack/Flutterwave: switch webhook + keys to live mode together — test
   keys with live webhooks (or vice versa) fail verification by design.

## Security gates satisfied

- No secret values in Git, frontend bundles, logs, or error responses; config
  introspection reports names only.
- No plaintext OTP anywhere in code paths or logs (hashed with per-phone
  pepper; delivery ledger stores provider metadata only).
- Webhook authenticity enforced before any state mutation; raw body preserved.
- Server-side transaction verification enforced; webhook payloads never trusted.
- Idempotency enforced (replays, races, duplicates credit exactly once).
- Amount/currency/reference/ownership validated server-side.
- Unknown provider state never treated as success (SMS and payments).
- Provider failures cannot corrupt wallet state (single-transaction settlement,
  fail-closed on verification errors).
- Audit events exist for settlement, reversals, risk decisions, and OTP abuse;
  the delivery ledger covers every provider attempt.
