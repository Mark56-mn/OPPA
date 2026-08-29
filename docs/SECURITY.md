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

## Database

Row-level security is enabled on security-sensitive tables. Application migrations must be reviewed before production execution.
