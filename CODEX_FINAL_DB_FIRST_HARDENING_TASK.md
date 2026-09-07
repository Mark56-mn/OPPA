# OPPA — FINAL HARDENING: DATABASE FIRST, THEN UI/INTEGRATION

## Mission
Execute this task **extremely fast, but extremely carefully**. The repository is at the V1 release-candidate stage, but the latest audit found important gaps between the committed code, the live Supabase database, and the mobile product integration.

**Order is mandatory:**
1. **Finish and verify the live database first.**
2. Then harden backend invariants and retry/idempotency behavior.
3. Then finish mobile integration/UI gaps.
4. Then perform final end-to-end/release verification.

Do not stop after the database work. Continue through all stages until complete or until credits genuinely run out.

## Critical rule about credentials
- **Never commit credentials, database passwords, service-role keys, provider secrets, OTP secrets, or tokens into the repository.**
- Do not request or invent public database credentials.
- Use environment variables / secure agent secrets for `DATABASE_URL` and other secrets.
- A Supabase publishable/anon key is not a database credential and must not be used as a substitute for privileged migration access.
- If a credential is needed for verification, record only the variable NAME and whether it is missing; never record its value.

## Known live-DB fact that must drive this task
The live Supabase project is `bqsovaxbjvgkdnwphprx`.

A live schema inspection on 2026-09-07 showed these public tables, but **no `oppa_calls` or `oppa_call_events` tables exist in the live database**, despite the repository containing the calls migration. This means the repository and live database are currently out of sync.

Live business tables include:
- `oppa_businesses`
- `oppa_business_products`
- `oppa_business_orders`
- `oppa_business_order_items`
- `oppa_business_staff`
- `oppa_business_customers`

Live PostgreSQL version is 17.6.

## Stage 1 — DATABASE FIRST (highest priority)

### 1. Inspect before changing
- Inspect `supabase/migrations` in the repo and compare against the actual live schema.
- Determine the exact migration history and which repository migrations are unapplied.
- Inspect tables, columns, primary keys, foreign keys, unique constraints, check constraints, indexes, triggers, functions, views, grants, RLS enablement, and RLS policies.
- Do not blindly recreate existing objects.
- Do not delete production data.
- Do not weaken existing security controls to make the app work.

### 2. Bring live DB to repository schema safely
Apply the repository's pending migrations using the project's normal migration mechanism. Prefer the existing migration runner/CLI process already documented in the repo.

Before applying:
- Check migration ordering and dependencies.
- Check whether each migration is idempotent or requires special handling.
- Back up/export schema metadata where practical.
- Never use destructive shortcuts such as dropping all tables.

After applying:
- Re-query the live DB and prove every expected object exists.
- Confirm calls tables now exist if their migration is valid.
- Confirm all expected business/payment/wallet/messaging/auth/session/security objects exist.

### 3. Fix the calls concurrency invariant in the database
The code currently expects a one-active-call-per-conversation invariant, but the live/repository schema audit found that the expected partial unique index was not actually present in the calls migration.

Add a proper database-level invariant for active/ringing calls per conversation, using the actual call status model in the repository.

Requirements:
- Must be enforced by PostgreSQL, not only application code.
- Must survive concurrent requests/races.
- Must have a regression test that proves two simultaneous starts cannot create two active/ringing calls for one conversation.
- Preserve valid historical completed/failed/cancelled calls.

### 4. Fix business order/product integrity
The current order-item relationship can reference a product belonging to a different business because `product_id` alone does not enforce the order's `business_id` matching the product's `business_id`.

Harden this at the database layer using the safest appropriate composite-key/FK or equivalent constraint design.

Acceptance:
- An order for Business A cannot contain a product from Business B.
- Valid same-business order items continue to work.
- Existing data must be checked before adding the constraint; if bad historical rows exist, report them and remediate safely rather than silently deleting them.

### 5. Verify grants/RLS/default privileges
The previous hardening migration revoked broad table/sequence/function privileges from `anon` and `authenticated`, but default privileges were not fully hardened.

Inspect:
- current table grants
- sequence grants
- function EXECUTE grants
- default privileges for object-creating roles
- RLS enabled state
- actual policies
- exposed Data API objects

The architecture is intended to use the privileged backend rather than direct client writes. Do **not** invent broad `auth.uid()` policies merely to silence an advisor. Instead, verify the intended architecture and ensure public/authenticated roles cannot bypass backend authorization.

If default privileges are unsafe, add a migration that safely hardens them for future objects without breaking the privileged backend.

### 6. Run Supabase security/advisor checks
After DB changes:
- run the project's supported advisor/security checks
- inspect every warning
- fix meaningful security findings
- distinguish intentional architecture findings from real defects
- verify schema after fixes

## Stage 2 — BACKEND HARDENING

### 7. Make retries endpoint-aware
The Flutter API client currently retries network/timeout/5xx responses generically. This is unsafe for non-idempotent operations such as payment initialization.

Implement a safe retry policy:
- GET/read requests: retry transient failures.
- Idempotent mutation: retry only when safely idempotent.
- Financial/non-idempotent operations: never blindly retry after an ambiguous transport failure unless protected by an idempotency key and server-side idempotency handling.
- Preserve bounded exponential backoff + jitter.
- Add tests for response-loss scenarios.

### 8. Make offline messaging lossless
The mobile outbound queue currently has a maximum size and may remove the oldest operation when full; exhausted retries can also drop pending operations.

Do not silently lose user messages.

Implement an explicit durable state model such as pending/retrying/blocked/failed that preserves the message and lets the user recover/retry. Financial operations must remain excluded from offline replay.

Acceptance:
- app restart does not lose pending messages
- repeated reconnect does not duplicate messages
- queue pressure does not silently delete messages
- failed operations remain inspectable/recoverable
- no financial request is placed in the offline mutation queue

### 9. Complete mobile business order lifecycle
The backend has fulfill/cancel order routes, but the mobile `BusinessRepository` was found not to expose both lifecycle operations.

Implement the missing repository/UI actions if they are intended for the mobile merchant/customer journey.

Verify:
- create/order
- pay
- fulfill
- cancel where allowed
- role checks
- status transitions
- idempotency
- audit/outbox behavior

## Stage 3 — CALLS / WEBRTC HONESTY

### 10. Finish or explicitly gate real call media
The current call service supports lifecycle/signaling event types but production audio/video media was not proven. Do not claim WebRTC is complete unless real offer/answer/ICE negotiation and media are actually wired and tested.

If implementing:
- support secure offer/answer/ICE signaling
- bind signaling to authenticated participants and call ID
- reject cross-call/cross-conversation injection
- handle permissions, ringing, answer, decline, busy, cancel, hangup, failure
- handle network degradation/reconnect
- prevent stale/replayed signaling
- never log SDP/ICE credentials or sensitive call payloads

If media cannot be completed in this run, explicitly mark it BLOCKED/NOT VERIFIED in the handoff; never mark it PASS.

## Stage 4 — UI / ANDROID VERIFICATION

The owner may import the repository into Google AI Studio / an Android-capable test environment to visually inspect the mobile app. Treat that as a real acceptance check, not proof that the UI is perfect.

### 11. Verify the actual committed Flutter UI
Inspect the actual `apps/mobile` source and run Flutter analyze/tests/build where the environment permits.

Verify the UI against the OPPA product direction and repository requirements:
- onboarding/auth gate
- home
- contacts/connect
- chats/thread
- wallet
- business
- profile/me
- support & safety
- call screen
- loading/empty/error/offline states
- African/low-data/mobile-first behavior
- correct navigation and back behavior
- no fake success states
- no provider secrets in mobile

Do not claim the UI is an exact visual match unless there is an approved visual reference in the repository. The correct standard is: implementation must match the current OPPA product specification and all documented UI requirements.

### 12. OTP limitation
The OTP provider is currently unavailable/not working. Do not fake OTP delivery.

Create a clearly controlled development/test mechanism only if the repository already specifies one, and ensure it cannot ship as a production bypass.

For Android acceptance, if real OTP cannot be completed:
- test all pre-OTP UI and flows that do not require delivery
- document OTP as BLOCKED
- continue testing post-auth flows using a safe test account/session mechanism only if one already exists
- never hard-code a universal OTP or authentication backdoor

## Stage 5 — FINAL ADVERSARIAL PASS

Attack the complete system as:
- unauthenticated user
- authenticated user
- attacker with another user's IDs
- revoked device
- concurrent caller
- replay attacker
- merchant
- merchant staff with limited role
- customer
- admin without required permission
- malformed client
- offline/reconnecting client
- payment response-loss client

Test:
- IDOR/BOLA
- privilege escalation
- cross-business access
- duplicate mutation/replay
- race conditions
- wallet balance manipulation
- payment double-credit
- webhook forgery/replay
- session/device revocation
- notification leakage
- message duplication/loss
- call injection/race
- order lifecycle abuse
- rate limiting/abuse paths

## Stage 6 — VERIFICATION AND HANDOFF

Run as many of these as the environment supports:
- backend tests
- adversarial tests
- concurrency tests
- TypeScript typecheck
- build
- static/security scans
- migration verification
- DB schema verification
- API smoke tests
- Flutter analyze
- Flutter tests
- Android build
- Android install/device acceptance
- end-to-end journeys

### Completion rule
Do not declare V1 complete if any critical/high defect remains.

If an environment limitation prevents a check, record:
- exact check
- exact blocker
- exact environment requirement
- what was verified instead
- risk level

### Credit exhaustion rule
If credits run out:
1. Commit and push all completed safe work.
2. Update `CODEX_HANDOFF.md` with exact completed/partial/not-done work.
3. List files changed.
4. List commits.
5. List verification results.
6. List remaining blockers and next exact commands/tasks.
7. Never claim blocked work as complete.

## Speed discipline
- Work in focused batches.
- Do independent read-only inspections in parallel where safe.
- Never run conflicting writes to the same file or DB object in parallel.
- Avoid unnecessary refactors.
- Preserve working behavior.
- Prefer the smallest secure change that closes the defect.
- Verify immediately after each DB/security change.
- Do not spend time polishing documentation before functional/security work is complete.

## Final response to owner
Report:
1. current commit SHA
2. DB migration/application status
3. DB objects/constraints added or changed
4. backend hardening completed
5. mobile/UI changes
6. tests and exact results
7. Android/OTP status
8. remaining BLOCKED/NOT VERIFIED items
9. exact next step if anything remains
