# OPPA Authentication Flow

1. Client submits a normalized phone number.
2. Backend applies OTP cooldown and hourly limits.
3. Backend generates and hashes a random OTP.
4. Backend stores only the hash and expiry.
5. Backend submits the OTP through the configured SMS provider.
6. Client submits the code.
7. Backend verifies and consumes the OTP.
8. A verified OPPA identity is created or restored.
9. A device cryptographic public key is registered.
10. A server-side session is created.

The client never receives the OTP from OPPA and no development bypass exists.

Device private keys must remain on the device and must never be sent to the API.
