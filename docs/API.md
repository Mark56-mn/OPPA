# OPPA API

## Authentication

### POST /auth/otp/request

Request:
{ "phone": "+2348012345678" }

Response:
- 202 with a challenge identifier
- 400 for invalid phone input
- 429 when an OTP is active or rate limits are exceeded

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
