# OPPA Codex Autopilot — Master Build Contract

## Mission
Build OPPA module-by-module as a production-oriented African mobile-first messaging, identity, wallet, payments, business and connectivity platform. Work for long autonomous sessions when Codex credits/time are available.

## Operating rule
Do NOT stop after every tiny task. Inspect the repository, implement coherent batches, test them, and continue to the next unfinished item. When credits/time expire, leave the repository in a buildable state and commit all completed work.

## Source of truth
Treat the existing repository, migrations, tests, and project requirements as the primary implementation source. Do not delete or overwrite newer work blindly. Resolve conflicts by inspecting the current file first.

## Non-negotiable engineering rules
1. Security before convenience.
2. Server is authoritative for identity, permissions, balances, payments and sensitive state.
3. Never trust client-side payment success, balances, roles or security decisions.
4. Sensitive operations must have authentication, authorization, validation, idempotency and auditability.
5. Financial mutations must be atomic and concurrency-safe.
6. Secrets never enter source control, mobile bundles, logs or tests.
7. Use parameterized SQL.
8. Fail closed on missing security dependencies.
9. Do not invent cryptography; use reviewed primitives/libraries and keep protocol boundaries explicit.
10. Preserve replaceable provider interfaces for SMS, payments, storage and external messaging.
11. Avoid unnecessary dependencies.
12. Every module must have tests for happy paths, invalid input, authorization failures and replay/concurrency risks where applicable.
13. Do not claim a build/test/deployment passed unless it was actually executed.
14. Before changing a file, inspect its current repository version/sha.
15. Do not silently weaken an existing security control to make tests pass.

## Current architecture
Cloudflare -> Render API/worker -> Supabase PostgreSQL, with provider adapters for SMS/payments and object storage. Frontend/mobile clients communicate through authenticated API boundaries.

## Master module roadmap

### 1. Identity & Authentication
- Phone OTP
- OTP hashing/expiry/attempt limits/rate limits
- identity creation
- device registration
- session issuance/rotation/revocation
- bearer authentication
- recovery
- anti-enumeration
- suspicious login controls

### 2. Messaging
- profiles/contacts
- direct conversations
- groups
- message persistence
- pagination
- realtime delivery
- offline sync
- media
- notifications
- E2EE architecture using established cryptographic protocols; never invent a protocol

### 3. Wallet
- wallet accounts
- integer minor-unit amounts
- atomic ledger
- idempotency
- transfer
- limits
- recipient validation
- concurrency protection
- transaction history
- reconciliation

### 4. Payments
- provider abstraction
- Paystack/Flutterwave adapters where configured
- initialization
- server-side verification
- webhook signature verification
- idempotent settlement
- wallet credit
- refunds/reversals
- reconciliation
- risk controls

### 5. Security Core
- device-bound keys
- sessions/devices
- step-up authentication
- sensitive-operation authorization
- security events
- security center
- recovery
- security alerts
- emergency controls

### 6. Risk & Abuse
- rate limiting
- OTP abuse
- rapid account creation
- failed transaction patterns
- account takeover signals
- device anomalies
- velocity limits
- merchant risk
- rule-based scoring first, extensible later
- review/block decisions with audit trail

### 7. Notifications & Event Delivery
- notification preferences
- in-app notifications
- security alerts
- transaction events
- delivery abstraction
- retry/idempotency
- background jobs/queue
- provider failure handling

### 8. Admin & Control Center
- RBAC
- super admin / operations / finance / security / support / developer / auditor roles
- append-only audit trail
- restricted audit viewer
- support cases
- emergency controls
- dual approval for consequential controls where appropriate

### 9. Business
- merchant profiles
- customers
- products
- orders
- payments
- analytics
- merchant permissions
- fraud controls

### 10. WhatsApp / Calls / Connectivity
- only technically authorized integrations
- explicit consent
- disconnect/revocation
- provider abstraction
- calls architecture
- OPPA Browser later
- VPN is V2, not V1

### 11. Operations & Launch
- /health /readiness /version
- Render deployment
- migrations
- monitoring
- backups
- recovery
- secret rotation
- alerting
- production QA
- legal/trust integration
- launch checklist

## Current known repository state
Existing backend foundation includes authentication, devices, sessions, profiles, contacts, conversations, messaging, wallet and payments. Security Core has step-up challenges, active-device checks, device-bound signature verification, sensitive-operation authorization, wallet transfer authorization and payment reversal authorization.

## Current priority
Finish verification/integration of Security Core, then proceed to Risk & Abuse and Notifications/Event Delivery. Do not move forward merely because files exist; move when the module boundary is tested and safe.

## Autonomous Codex instructions
When started:
1. Inspect current git status, branches and recent commits.
2. Read this file.
3. Read relevant existing module files before modifying them.
4. Create an implementation checklist for the current module.
5. Execute independent tasks in parallel where safe.
6. Run available typecheck/build/tests after coherent batches.
7. Fix failures before adding unrelated functionality.
8. Audit security boundaries and data-flow after implementation.
9. Commit coherent changes with descriptive messages.
10. Continue to the next unfinished checklist item without waiting for user confirmation.
11. If credits are exhausted, stop only after saving/committing completed work and leave a concise handoff in CODEX_HANDOFF.md.
12. Never fabricate external verification.

## Handoff format
If the autonomous session ends, update CODEX_HANDOFF.md with:
- completed work
- files changed
- commits
- tests actually run and results
- unresolved failures
- security concerns
- exact next tasks
- any manual action required from the owner

## Audit mode
After Codex stops, the next agent must audit the repository rather than assuming Codex work is correct. Inspect diffs, tests, migrations, security boundaries and dependency changes. Re-run available checks. Identify vulnerabilities, incomplete wiring and false completion claims. Fix only after understanding the current state.

## Definition of done for every module
A module is done only when:
- implementation exists
- API boundaries are wired
- persistence is correct
- authorization is enforced
- failure paths are handled
- idempotency/concurrency is addressed where relevant
- tests cover abuse/invalid paths
- build/typecheck passes when executable
- deployment configuration is compatible
- no known critical security bypass remains
- handoff/audit notes are updated
