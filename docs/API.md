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
