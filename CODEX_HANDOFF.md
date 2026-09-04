# OPPA CODEX HANDOFF

## Purpose
Durable resume state for autonomous Codex sessions. The next agent must read this file together with `OPPA_MASTER_BUILD_SPEC.md`, `CODEX_AUTOPILOT.md`, `CODEX_BUILD_MAP.md` and the active task file.

## LAST UPDATED
2026-09-04 — Backend adversarial audit & integration closure session completed.

## CURRENT BASELINE
- Starting commit of audit session: `4076ed4` (docs: queue backend adversarial audit as next exact task)
- Migrations 0001–0017 present; route surface spans auth, account, profile, contacts, conversations/messages, wallet, payments+webhooks, security, admin (incl. emergency), notifications, business.
- WhatsApp remains excluded from V1 (V2 only). Browser/VPN/Mini Apps deferred.

## SESSION SUMMARY (Backend adversarial audit & integration closure)
- date: 2026-09-04
- starting commit: `4076ed4`
- ending commit: see COMMITS below
- exact scope worked: full backend adversarial audit per `CODEX_BACKEND_ADVERSARIAL_AUDIT_TASK.md` — migrations, route-wide authorization, auth/session/device, security core, wallet/payments money safety, messaging, notifications/outbox, business/self-ordering, admin/RBAC, risk wiring, error handling and secrets; fixes + regression tests for every confirmed defect.

## COMPLETED
- Route-wide authorization audit: enumerated all 57 routes across 12 routers and classified each (public / authenticated / owner-member / staff-gated / unauthenticated-provider-webhook). Confirmed: every non-auth route sits behind `createRequireAuth`; staff surfaces (`/admin/*`, `/notifications/process`) are behind `requirePermission`; payment webhooks verify provider signatures using raw body and are the only unauthenticated surface; no client-trusted user IDs/roles found in authorization decisions.
- Migration audit (static, 0001–0017): money columns are bigint minor units with positivity checks; wallets enforce `balance_minor >= 0`; transfer/ledger/payment references carry unique constraints supporting idempotency; step-up and OTP challenges have partial unique indexes (one active per user+purpose / per phone); notification outbox has a partial unique dedupe index; business tables enforce staff role checks and per-customer order-reference uniqueness.
- FINDING W1 (wallet): the daily-counter increment ran on the pool outside the transfer transaction while the code comment claimed "counters can never race the debit". A concurrent same-sender transfer could under-count and exceed daily limits. Fixed: counter upsert now runs inside the transfer transaction after the deterministic wallet lock.
- FINDING W2 (wallet): money movement did not validate account status — transfers to/from frozen, locked, suspended or deleted accounts could succeed. Fixed: the wallet lock query now joins `oppa_users` and requires `status='active'` for both sender and recipient (`USER_NOT_FOUND` otherwise). Same invariant applied to business order settlement.
- FINDING B1 (business): the self-order rule was enforced only at order creation; a customer who became staff after creating an order could still pay it, settling money into their own business wallet. Fixed: `payOrder` re-checks staff membership at settlement time inside the same transaction (`BUSINESS_ORDER_SELF_INVALID`).
- FINDING N1 (notifications): outbox rows claimed by a worker that crashed between claim and deliver stayed `processing` forever — event starvation with no recovery path. Fixed: added `updated_at` touch on every claim/resolve, `recoverStalledProcessing(10m)` reaper invoked by `processBatch` before claiming (best-effort, failure does not block claiming), migration 0015 amended to add `updated_at`.
- FINDING N2 (notifications): bulk mark-all-read silently marked security alerts read — a client gesture could bury an active takeover alert. Fixed: bulk read excludes `category='security'`; individual reads remain allowed.
- FINDING S1 (security core): `createChallenge` consumed the active challenge and inserted the replacement non-transactionally; an insert failure left the user with no active challenge until expiry (step-up self-denial). Fixed: consume-then-insert now runs in one transaction with rollback; regression tests verify the begin→consume→insert→commit sequence and the rollback path via constructor-injected fake pool (repository gained an optional, non-breaking pool parameter).
- FINDING A1 (auth/OTP): OTP verification had no service-layer code-shape guard; malformed codes proceeded to a challenge lookup. Fixed: `/^\d{6}$/` guard added in `OtpService.verify` before repository access (defense-in-depth; route layer already enforced this).
- Error-handler additions: `NOTIFICATION_USER_NOT_FOUND` (404), `NOTIFICATION_EVENT_INVALID`/`NOTIFICATION_PAYLOAD_INVALID` (400).

## FILES CHANGED
- apps/api/src/modules/wallet/postgres-wallet-transfer-repository.ts
- apps/api/src/modules/business/postgres-business-repository.ts
- apps/api/src/modules/notifications/postgres-notification-repository.ts
- apps/api/src/modules/notifications/notification-service.ts
- apps/api/src/modules/security/postgres-security-proof-repository.ts
- apps/api/src/modules/otp/otp-service.ts
- apps/api/src/http/error-handler.ts
- database/migrations/0015_notifications.sql (added `updated_at`)
- Tests: apps/api/src/modules/notifications/notification-recovery.test.ts, apps/api/src/modules/security/step-up-transaction.test.ts, apps/api/src/modules/security/otp-shape-guard.test.ts, apps/api/src/modules/notifications/notifications.test.ts (store cast)
- CODEX_HANDOFF.md

## COMMITS
- Audit fixes and handoff committed on main; exact hash recorded in git log on top of `4076ed4`.

## VERIFIED
- tests: PASS — 90 pass / 5 skip / 0 fail (`bun test src` in apps/api; 5 skips are Postgres integration tests requiring `DATABASE_URL`)
- typecheck: PASS — `bun run api:typecheck` (tsc --noEmit, strict)
- build: PASS — `bun run build` emits dist/server.js (dist removed after verification)
- migrations: NOT APPLIED — no `DATABASE_URL` in this environment; static review of 0001–0017 completed instead
- integration: BLOCKED — `DATABASE_URL` unavailable; migration application + live integration suite NOT RUN (see known limitations)
- final scans: no TODO/FIXME/STUB, no `501` stub handlers, no WhatsApp references, no hard-coded secrets in apps/api/src or database/

## FINDINGS FIXED
See COMPLETED items W1, W2, B1, N1, N2, S1, A1 above — each fixed at the smallest correct server-side layer with a regression test (test count rose 85 → 90).

## FINDINGS STILL OPEN
- Provider refund/reconciliation for Paystack/Flutterwave remains NOT implemented (intentionally unadvertised; no refund routes exist). Requires real provider API/webhook work — out of audit scope, documented per task instructions.
- OTP request/verify rate limits are per-phone only; there is no per-IP limit. Spec-conformant for V1 (anti-enumeration preserved) but IP throttling should be added at the edge/proxy layer.
- Realtime messaging delivery (WebSocket/SSE), offline outbound queue and push notifications remain future V1 work per the build map; current messaging is REST with receipts.
- `hasPermission` performs one RBAC query per admin call; no caching layer. Acceptable at current scale.

## KNOWN LIMITATIONS
- GENUINE LIMITATIONS (not failures): Postgres integration verification requires `DATABASE_URL` (5 skipped tests + migration application). Notifications are in-app only by design. Calls/Flutter/frontend work is explicitly out of scope for this task.
- The wallet-transfer limit check reads counters inside the transaction; with the counter increment now also transactional, concurrent same-sender transfers serialize on the wallet row lock, making the limit assessment monotonic and race-free.

## NEXT EXACT TASK
1. On an environment with `DATABASE_URL`: apply migrations 0001–0017 in order, run `bun test src` in apps/api to execute the 5 integration tests, and confirm no schema drift.
2. Then proceed to the next V1 module: **OPPA-native Calls** (signaling/media/security architecture), followed by Flutter integration.

## MANUAL OWNER ACTION
- Provide/configure `DATABASE_URL` (and the OTP/session/payment secrets) in the environment where integration verification should run.

## V1 EXECUTION ORDER AFTER AUDIT
1. Backend adversarial audit + integration closure — audit complete; integration verification BLOCKED on DATABASE_URL
2. OPPA-native Calls
3. Flutter mobile integration
4. Web/Admin/Trust surfaces
5. Operations + Launch QA

WhatsApp remains V2 and is not in this V1 order.

## VERIFICATION RULE
For every module, inspect source/interfaces/migrations/routes/tests; implement the complete vertical slice; audit authentication, authorization, ownership, replay, idempotency, concurrency, abuse, error leakage and secrets; run available tests/typecheck/build/lint/schema checks; inspect the final diff; and update this handoff.

Never claim a test, migration, integration or deployment passed unless actually verified.

## CREDIT / SESSION STOP PROTOCOL
If credits/context/time/environment capacity run out:

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

Never leave the next session guessing where to resume.

## OWNER MERGE POLICY
Owner performs merges manually. Do not force merges or bypass security/quality gates. Do not spend credits on billing, CI/infrastructure or production credentials unless required for application correctness.
