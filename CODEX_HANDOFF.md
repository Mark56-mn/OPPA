# Codex Handoff

## Purpose
Durable handoff for autonomous Codex sessions. Update this file whenever a session ends because of credits, context, time, environment limits or interruption.

## Last initialized
2026-09-02

## Read first
1. `OPPA_MASTER_BUILD_SPEC.md` — complete application/product/build map.
2. `CODEX_AUTOPILOT.md` — autonomous operating contract.
3. This file — current durable session state.

## Current repository reality
The OPPA repository already contains a substantial TypeScript backend foundation under `apps/api/src`, including Auth/OTP/Identity/Device/Session/SMS, Profile, Contact, Messaging, Wallet, Payments, Admin and Security modules. Database migrations and Codex documentation are also present.

Do not rebuild the foundation blindly. Inspect the actual current branch, code, migrations and tests before changing anything.

## Session 2026-09-03 — Security Core intent binding closure (branch `codex/security-core-closure`)

SESSION STOP REASON: coherent Security Core batch verified and committed on a feature branch (owner requested no commits to main).

COMPLETED:
- Cryptographic intent binding for sensitive authorizations:
  - `apps/api/src/modules/security/intent-binding.ts` — canonical intent serialization (sorted keys) + sha256 intent hashing with depth/size guards.
  - `database/migrations/0012_security_intent_binding.sql` — `intent_hash` column on `oppa_step_up_challenges` + partial unique index enforcing exactly one active challenge per user+purpose.
  - `DeviceProofService` now verifies signatures over `challenge + "." + canonicalIntent` when the challenge was created with an intent; `SecurityService.createStepUp/consumeStepUp` accept and validate the intent.
  - Wallet transfer route derives the intent server-side (`toUserId`, `amountMinor`, `currency`, `reference`) so a captured proof cannot authorize different transaction parameters.
  - Payment reversal implemented end-to-end: `PaymentService.reverse()` (ownership check via new `PaymentRepository.findById`, intent-bound `payment_reversal` authorization, then atomic `reverseAndDebit`), protected `POST /payments/reverse` route, 401/404/409 mappings.
- Failure auditing: every rejected device proof and step-up consumption now increments attempts and records `security.device_proof_failed` / `security.step_up_failed` events with reasons (challenge_not_found, device_mismatch, challenge_invalid, intent_mismatch, device_key_unavailable, signature_invalid).
- Atomicity: concurrent consumption consumes exactly once (existing atomic UPDATE retained); concurrent challenge creation is now rejected with `STEP_UP_CHALLENGE_CONFLICT` (409) instead of silently leaving two active challenges.
- Tests: 50 total (45 pass, 5 Postgres integration tests added and skipped when `DATABASE_URL` is unset). New route-level HTTP tests for wallet transfer and payment reversal intent flow; extended unit tests for intent binding/failure events.
- CI: `.github/workflows/api.yml` now runs the full `npm test` suite instead of one OTP test.

FILES CHANGED (on branch `codex/security-core-closure`, not main):
- `database/migrations/0012_security_intent_binding.sql` (new)
- `apps/api/src/modules/security/intent-binding.ts` (new)
- `apps/api/src/modules/security/security-repository.ts`, `security-service.ts`, `device-proof-service.ts`, `sensitive-authorization.ts`, `default-sensitive-authorization.ts`, `security-routes.ts`, `postgres-security-repository.ts`, `postgres-security-proof-repository.ts`
- `apps/api/src/modules/wallet/wallet-routes.ts`, `apps/api/src/modules/payments/payment-service.ts`, `payment-routes.ts`, `payment-repository.ts`, `postgres-payment-repository.ts`
- `apps/api/src/http/error-handler.ts`, `.github/workflows/api.yml`, `docs/API.md`, `docs/SECURITY.md`
- Tests: `security-service.test.ts`, `device-proof-service.security.test.ts`, `sensitive-authorization.test.ts`, `wallet-routes.test.ts` (new), `payment-routes.test.ts` (new), `postgres-security-repository.test.ts` (new)

VERIFIED (executed in this session):
- test: PASS — `npm test` in `apps/api`: 45 pass, 0 fail, 5 skipped (Postgres integration tests; `DATABASE_URL` unset).
- typecheck: PASS — `npm run typecheck` (tsc --noEmit).
- build: PASS — `npm run build` (tsc).
- diff: PASS — `git diff --check`.

PARTIALLY COMPLETED:
- Provider-initiated payment refund webhooks remain stubbed (`501 PAYMENT_REVERSAL_NOT_IMPLEMENTED`); requires real provider refund API integration before advertising refunds.

NOT DONE:
- Postgres integration tests were written but NOT executed here (no `DATABASE_URL` in this environment). Run them where a database is configured.
- Risk & Abuse, Notifications/Event Delivery, Admin/Control Center, Business, WhatsApp/Calls, Flutter/web surfaces, Operations QA — per master roadmap order.

KNOWN FAILURES/RISKS:
- None known in the executed unit/route test suite.
- `bun.lock` is untracked at the repo root (environment artifact) and was intentionally left out of the commit.

NEXT EXACT TASK:
- Run `postgres-security-repository.test.ts` against a real database (`DATABASE_URL` set) to execute the 5 skipped integration tests, then start Risk & Abuse (module 6 of the roadmap).

MANUAL OWNER ACTION:
- Review branch `codex/security-core-closure` and open/merge the PR.
- Provide `DATABASE_URL` to run integration tests.

## Previous verified history (carried forward)
- API test suite restored to the repository's Node test runner.
- Device-proof verification validates the presented challenge hash before device signature verification.
- Persisted challenges are atomically consumed.
- Invalid signatures/unavailable active keys record/increment failures.
- Security validation failures map to intentional HTTP statuses.
- Server startup TypeScript issue fixed.
- `PostgresSecurityRepository` restored to active-device validation conformance.

Historical checks recorded as passed (must be rerun against the current repository before relying on them):
- `npm test --workspace @oppa/api` — 22 tests.
- `npm run api:typecheck` — passed.
- `npm run build` — passed.
- `git diff --check` — passed.

## Product/build target
Build the complete OPPA application described in `OPPA_MASTER_BUILD_SPEC.md`:

- phone-first identity/authentication;
- complete secure messaging;
- groups/media/realtime/offline sync/notifications;
- wallet and secure transfers;
- payment integrations, settlement, refunds/reconciliation;
- Security Core and recovery;
- Risk & Abuse;
- notifications/event delivery;
- Admin/Control Center;
- Business/merchant capabilities;
- authorized WhatsApp-connected capabilities and calls;
- Flutter mobile application;
- web/admin/trust surfaces;
- operations/launch readiness.

Three tokenized themes are required across the application:
- Fluid Africa
- OPPA Pulse
- Everyday OPPA

Browser is V1.5/later unless scope changes. VPN is V2. Mini Apps are post-V1.

## Next execution order
1. Inspect current Security Core state and git history.
2. Rerun build/typecheck/tests.
3. Add/finish route-level integration tests with real PostgreSQL where available.
4. Complete Security Core adversarial audit.
5. Complete Risk & Abuse.
6. Complete Notifications/Event Delivery.
7. Finish Admin/Control Center.
8. Finish Business.
9. Finish authorized WhatsApp/Calls.
10. Build/integrate Flutter mobile and web/admin surfaces against the real API.
11. Complete Operations/Launch QA.
12. Defer Browser/VPN/Mini Apps according to the master spec.

If a dependency requires a different order, record the reason and choose the safest executable path.

## Credit exhaustion protocol — mandatory

If Codex runs out of credits/context/time/environment capacity:

- do not start new work;
- save all coherent completed changes;
- run the fastest meaningful checks available;
- commit coherent work;
- update this file immediately;
- explicitly state completed vs partial vs not done work.

Use this exact structure:

```text
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
```

Never claim completion for unverified work. Never leave the next session guessing where to resume.

## Security reminder
Never expose secrets. Never put provider credentials in Flutter or GitHub. Never invent cryptography or bypass platform/provider controls. Never let the client decide financial settlement or security authorization.
