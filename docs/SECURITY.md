# OPPA Security Baseline

The authentication boundary must never expose OTP values, OTP hashes, provider credentials, refresh tokens, or other secrets to clients or logs.

## OTP

- OTPs are cryptographically random.
- OTPs are stored only as hashes.
- OTPs expire.
- OTPs are single-use.
- Verification attempts are limited.
- Requests are rate-limited.
- Failed SMS submission invalidates the challenge.
- There is no development OTP bypass.

## Provider boundary

SMS delivery is isolated behind the SmsProvider interface. Provider-specific request formats and credentials must not leak into authentication business logic.

## Sessions

Refresh tokens must be stored only as hashes. Session revocation is server-side. Device identity is separate from user identity.

## Sensitive-operation authorization (step-up)

- Step-up challenges are short-lived (5 minutes), single-use, and limited to 5 attempts.
- Challenges are stored only as hashes; the raw challenge is never persisted.
- Only one active challenge per user + purpose exists; issuance and consumption are atomic.
- Challenges can be cryptographically bound to the exact operation intent (recipient, amount, currency, reference): the stored `intent_hash` must match the intent presented at proof time, and the device signature must cover `challenge + "." + canonicalIntent`.
- The server derives the intent from its own validated inputs; a captured proof cannot be replayed against different transaction parameters.
- Every rejected proof increments the attempt counter and writes a `security.device_proof_failed` / `security.step_up_failed` event with the reason.
- Sensitive endpoints fail closed (503) when the sensitive-authorization dependency is unavailable.

## Money movement safety

- Wallet transfers are idempotent, atomic (deterministic wallet locking) and never trust client-side balances.
- Per-user transfer limits (single, daily total, daily count) are enforced inside the same transaction that moves money; the daily counters are incremented atomically with the transfer and can never race the debit.
- Operator-issued risk decisions (`user`/`transfer` scopes) are checked before any transfer; a `block` decision fails the transfer closed.
- Payment settlement credits the wallet only after provider webhook signature verification, provider-side verification, and a risk decision computed from real recent payment counts (no hardcoded assumptions). Operator `payment` blocks/reviews stop settlement before credit.
- Every blocked transfer and blocked/reviewed payment writes a risk event (`transfer_velocity` / `payment_anomaly`) with the reason.
- OTP rate limiting and attempt exhaustion write `otp_abuse` risk events.
- Risk events and operator decisions are append-only records; decisions expire when configured.

## Database

Row-level security is enabled on security-sensitive tables. Application migrations must be reviewed before production execution.
