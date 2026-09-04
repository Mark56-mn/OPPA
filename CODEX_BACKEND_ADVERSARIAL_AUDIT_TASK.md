# OPPA V1 — BACKEND ADVERSARIAL AUDIT & INTEGRATION CLOSURE

## Mission

You are Codex operating on the current `main` branch of OPPA. Your immediate job is **not** to start Flutter, Calls, WhatsApp, UI, CI, billing, or infrastructure.

Your job is to make the existing V1 backend foundation trustworthy by performing a **full adversarial security/correctness audit and closing every real issue you find**, then proving the result with tests and integration verification.

Read these first:

1. `OPPA_MASTER_BUILD_SPEC.md`
2. `CODEX_AUTOPILOT.md`
3. `CODEX_BUILD_MAP.md`
4. `CODEX_HANDOFF.md`
5. this file

Do not trust previous agent summaries blindly. Inspect the actual source, migrations, routes, repositories, services and tests on the current branch.

---

## HARD SCOPE LOCK

### Allowed
- Backend/API source
- Database migrations/schema
- Backend tests and fixtures
- Backend security/correctness documentation
- `CODEX_HANDOFF.md`

### Explicitly forbidden in this task
- WhatsApp / WhatsApp Business API / Cloud API / account linking / WhatsApp inbox / scraping
- Flutter/mobile UI
- Web/Admin/Trust frontend
- OPPA Calls implementation
- CI/CD or production infrastructure
- Billing or paid infrastructure
- Production credentials
- Unrelated refactors

If a discovered issue genuinely requires a forbidden area, document it in the handoff instead of expanding scope.

---

# PRIMARY OBJECTIVES

## 1. Establish the real baseline

Inspect the current tree and determine:

- current commit
- current migrations
- current route surface
- current authentication/session/device model
- current wallet/payment model
- current messaging/notification/business/admin model
- current tests and integration-test requirements
- uncommitted changes, if visible

Do not assume historical test counts or previous handoff claims are still true.

## 2. Database and migration closure

Audit **all migrations**, with special attention to 0014–0017 and everything they depend on.

Verify:

- migration ordering
- foreign keys
- unique constraints
- check constraints
- indexes
- partial unique indexes
- nullable vs non-nullable fields
- monetary integer/minor-unit representation
- timestamps
- cascade/restrict behavior
- append-only audit/event records where required
- idempotency/deduplication constraints
- transaction boundaries
- indexes needed for authorization and locking queries

If `DATABASE_URL` is available, apply migrations to a disposable/test database and run the integration suite.

If `DATABASE_URL` is unavailable, do **not** claim DB integration passed. Perform static migration review and record the exact blocked verification.

## 3. Authentication, identity, sessions and devices

Adversarially test:

- OTP enumeration
- OTP replay
- OTP brute force
- OTP expiry
- refresh-token replay/rotation
- revoked sessions
- revoked devices
- cross-user device IDs
- device proof misuse
- challenge reuse
- challenge expiry
- challenge attempt limits
- step-up purpose confusion
- token/session binding
- account recovery abuse
- authorization after account/device/session state changes

Look for IDOR/BOLA, privilege escalation, stale authorization and information leakage.

## 4. Security Core / sensitive authorization

Audit every sensitive operation, especially:

- wallet transfer
- payment reversal
- security changes
- account recovery

Verify that:

- the server derives the canonical intent from validated request data;
- client-supplied authorization context cannot substitute for server-derived intent;
- proofs/challenges cannot be replayed across operations/users/purposes;
- device proof is bound to the correct active device/user;
- consumed challenges cannot be reused;
- failed attempts are bounded and audited;
- errors do not reveal unnecessary security state.

## 5. Wallet and ledger

Treat money safety as the highest priority.

Audit:

- integer minor units only
- positive amount validation
- overflow/unsafe integer handling
- sender balance locking
- concurrent transfers
- self-transfer behavior
- recipient ownership
- nonexistent/deactivated recipients
- duplicate references/idempotency
- transaction atomicity
- rollback behavior
- ledger balance consistency
- daily/transaction limits
- risk blocks/review
- authorization before mutation
- notification/outbox side effects
- double debit/double credit possibilities

Create concurrency/regression tests where useful.

A request must never be able to create money merely by racing two requests or retrying a request.

## 6. Payments

Audit Paystack/Flutterwave abstractions and payment lifecycle.

Verify:

- provider transaction identity
- amount/currency matching
- webhook signature verification
- raw-body handling
- duplicate webhook idempotency
- replayed webhook behavior
- unknown transaction handling
- wallet settlement atomicity
- failed/pending/success state transitions
- reversal authorization
- refund/reversal boundaries
- provider mismatch attacks
- user/account ownership
- notification/outbox side effects

Do not invent provider behavior. If production reconciliation/refund functionality remains incomplete, document it precisely rather than pretending it is complete.

## 7. Messaging

Audit every conversation/message endpoint.

Check:

- membership authorization
- sender ownership
- recipient privacy
- message edit/delete authorization
- group owner/admin permissions
- add-member authorization
- leave behavior
- read/receipt privacy
- unread counts
- deleted-message handling
- cross-conversation IDOR/BOLA
- enumeration through errors
- pagination/order consistency
- duplicate/replayed writes
- race conditions around membership and message mutation

A user must never read or mutate another conversation/message merely by guessing an ID.

## 8. Notifications and outbox

Audit:

- transactional outbox writes
- dedupe keys
- worker claiming
- `SKIP LOCKED` behavior
- retry/backoff
- failure handling
- duplicate delivery
- notification authorization
- preference enforcement
- sensitive payload leakage
- worker lifecycle
- manual processing endpoint permissions

Never put OTPs, access/refresh tokens, signatures or unnecessary financial/security secrets into notifications.

## 9. Business / Merchant

Audit:

- business ownership
- staff role boundaries
- staff invitation/management authorization
- product ownership
- order ownership
- customer permissions
- merchant wallet settlement
- ledger entries
- duplicate order creation
- concurrent settlement
- cancellation/refund boundaries
- analytics information leakage
- merchant/customer cross-tenant access

### Mandatory self-order rule

A merchant owner/staff member must **not** be able to create a normal customer order against their own business.

This must be enforced server-side, not merely in UI.

Add/retain adversarial regression tests proving that:

- owner self-order is blocked;
- staff self-order is blocked;
- another legitimate customer can still order;
- guessing a business/order ID cannot bypass authorization.

## 10. Admin / emergency controls / RBAC

Audit every admin endpoint for:

- authentication
- permission checks
- role boundaries
- target ownership/scope
- self-targeting restrictions
- reason requirements
- confirmation requirements
- audit logging
- append-only semantics
- information leakage
- privilege escalation

Pay special attention to emergency actions such as freeze/unfreeze user, revoke sessions, and suspend/restore business.

A normal user must never reach an admin operation through route manipulation or object-ID guessing.

## 11. Route-wide authorization audit

Do not only inspect recently modified modules.

Enumerate **every API route** and classify it:

- public
- authenticated user
- resource owner/member
- staff
- admin
- super-admin
- internal/background only

For every route, verify the implementation actually enforces the intended class.

Search specifically for:

- missing auth middleware
- missing permission checks
- missing ownership checks
- trust of client-provided user IDs
- trust of client-provided roles
- IDOR/BOLA
- privilege escalation
- unsafe error details
- unbounded input
- replayable state-changing requests

## 12. Abuse/risk wiring

Check whether risk/abuse signals are actually connected to the paths they are supposed to protect.

Look for dead code where a risk detector exists but is never invoked.

Pay particular attention to:

- registration/login
- OTP abuse
- device anomalies
- transfers
- payments
- merchant/order abuse
- spam/messaging abuse

Only wire signals where the current V1 specification supports them. Do not invent product behavior.

## 13. Error handling and secrets

Audit for:

- stack traces in production responses
- database errors leaked to clients
- provider secrets in responses/logs
- hard-coded secrets
- tokens/signatures in logs
- overly descriptive auth failures
- unsafe error serialization
- unsafe environment defaults

Use safe, stable error codes/messages consistent with the existing architecture.

---

# FIX POLICY

When you find a real defect:

1. Understand the intended invariant.
2. Fix the smallest correct layer.
3. Prefer server-side enforcement.
4. Preserve existing public contracts unless the contract itself is unsafe.
5. Add a regression/adversarial test.
6. Re-run the relevant tests.
7. Continue auditing instead of stopping after the first bug.

Do not paper over a failure with weaker assertions or skipped tests.

Do not delete security tests merely to get green output.

Do not silently weaken authorization.

Do not add speculative abstractions with no immediate use.

---

# VERIFICATION GATE

Before declaring this task complete, run what the environment supports:

- unit/integration tests
- typecheck
- build
- lint if configured
- migration/schema verification
- targeted adversarial tests
- final source/diff scan

At minimum, search the final source for:

- TODO
- FIXME
- STUB
- `501`
- placeholder handlers
- disabled security checks
- hard-coded secrets
- WhatsApp references accidentally introduced by this task

Do not claim a command passed unless you actually ran it.

For DB verification:

- `DATABASE_URL` available + migrations/tests executed = report exact result;
- no `DATABASE_URL` = explicitly report DB integration as NOT VERIFIED/BLOCKED.

---

# HANDOFF REQUIREMENT — MANDATORY

At the end, update `CODEX_HANDOFF.md` with the real state.

Include:

## SESSION SUMMARY

- date
- starting commit
- ending commit
- exact scope worked

## COMPLETED

Bullet list of concrete fixes/audits.

## FILES CHANGED

Exact paths.

## COMMITS

Exact commit hashes/titles if commits were made.

## VERIFIED

- tests: PASS/FAIL/PARTIAL/NOT RUN
- typecheck: PASS/FAIL/PARTIAL/NOT RUN
- build: PASS/FAIL/PARTIAL/NOT RUN
- migrations: APPLIED/NOT APPLIED/PARTIAL
- integration: VERIFIED/BLOCKED/FAILED

Include exact counts/output where practical.

## FINDINGS FIXED

List important vulnerabilities/bugs discovered and how they were fixed.

## FINDINGS STILL OPEN

List every unresolved issue, even if minor.

## KNOWN LIMITATIONS

Separate genuine limitations from failures.

## NEXT EXACT TASK

Give the next agent one concrete next action, not a vague roadmap.

## MANUAL OWNER ACTION

Only if something truly requires the owner.

---

# CREDIT / CONTEXT EXHAUSTION PROTOCOL

If credits, context, time or environment capacity run out, STOP cleanly and update `CODEX_HANDOFF.md` before stopping.

Use this exact structure:

SESSION STOP REASON: credits/time/context/environment

COMPLETED:
- ...

FILES CHANGED:
- ...

COMMITS:
- ...

VERIFIED:
- test: PASS/FAIL/NOT RUN
- typecheck: PASS/FAIL/NOT RUN
- build: PASS/FAIL/NOT RUN
- migrations: APPLIED/NOT APPLIED/PARTIAL
- integration: VERIFIED/BLOCKED/FAILED

PARTIALLY COMPLETED:
- ...

NOT DONE:
- ...

KNOWN FAILURES/RISKS:
- ...

NEXT EXACT TASK:
- ...

MANUAL OWNER ACTION:
- ...

Never leave the next agent guessing.

---

# DEFINITION OF DONE

This task is done only when:

1. The current backend has been audited rather than assumed correct.
2. Real security/correctness defects found in scope are fixed.
3. Regression/adversarial tests cover the important fixes.
4. Wallet/payment invariants are protected against replay and concurrency.
5. Route authorization has been reviewed globally.
6. Merchant self-ordering is server-side blocked.
7. Admin controls are authorization-safe and audited.
8. Messaging privacy/ownership is enforced.
9. Notification/outbox behavior is idempotent and permission-safe.
10. Migrations have been tested if a DB is available, or explicitly marked unverified if not.
11. Tests/typecheck/build have been run and honestly reported.
12. `CODEX_HANDOFF.md` accurately records the result and next exact task.

Only after this gate is satisfied should the project move to the next V1 module.
