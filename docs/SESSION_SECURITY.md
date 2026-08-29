# OPPA Session Security

- Access tokens are short-lived.
- Refresh tokens are high-entropy random values.
- Only refresh-token hashes are persisted.
- Session records can be revoked server-side.
- Device identity is separate from user identity.
- An authenticated middleware must reject missing credentials before protected resources.
- A bearer token must never be logged or returned in error messages.

The access-token verifier remains a required implementation step before protected production resources are exposed.
