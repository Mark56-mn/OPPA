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

## Session 2026-09-03 (first) — Security Core intent binding closure (branch `codex/security-core-closure`, PR #5, now rebased on PR #4)

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
- Tests: 53 total (48 pass, 5 Postgres integration tests added and skipped when `DATABASE_URL` is unset). New route-level HTTP tests for wallet transfer and payment reversal intent flow; extended unit tests for intent binding/failure events.
- CI: `.github/workflows/api.yml` now runs the full `npm test` suite instead of one OTP test.

FILES CHANGED (on branch `codex/security-core-closure`, not main):
- `database/migrations/0012_security_intent_binding.sql` (new; supersedes PR #4's `0012_sensitive_context_binding.sql`, which is removed)
- `apps/api/src/modules/security/intent-binding.ts` (new)
- `apps/api/src/modules/security/security-repository.ts`, `security-service.ts`, `device-proof-service.ts`, `sensitive-authorization.ts`, `default-sensitive-authorization.ts`, `security-routes.ts`, `postgres-security-repository.ts`, `postgres-security-proof-repository.ts`
- `apps/api/src/modules/wallet/wallet-routes.ts`, `apps/api/src/modules/payments/payment-service.ts`, `payment-routes.ts`, `payment-repository.ts`, `postgres-payment-repository.ts`
- `apps/api/src/http/error-handler.ts`, `.github/workflows/api.yml`, `docs/API.md`, `docs/SECURITY.md`
- Tests: `security-service.test.ts`, `device-proof-service.security.test.ts`, `sensitive-authorization.test.ts`, `wallet-routes.test.ts` (new), `payment-routes.test.ts` (new), `postgres-security-repository.test.ts` (new)

VERIFIED (executed in this session):
- test: PASS — `npm test` in `apps/api`: 48 pass, 0 fail, 5 skipped (Postgres integration tests; `DATABASE_URL` unset).
- typecheck: PASS — `npm run typecheck` (tsc --noEmit).
- build: PASS — `npm run build` (tsc).
- diff: PASS — `git diff --check`.

PARTIALLY COMPLETED:
- Provider-initiated payment refund webhooks remain stubbed (`501 PAYMENT_REVERSAL_NOT_IMPLEMENTED`); requires real provider refund API integration before advertising refunds.

NOT DONE:
- Postgres integration tests were written but NOT executed here (no `DATABASE_URL` in this environment). Run them where a database is configured.

KNOWN FAILURES/RISKS:
- None known in the executed unit/route test suite.
- `bun.lock` is untracked at the repo root (environment artifact) and was intentionally left out of the commit.

NEXT EXACT TASK:
- Merge PR #4, then this branch (PR #5) — they now stack cleanly with the intent-binding feature reconciled to a single implementation.

MANUAL OWNER ACTION:
- Review PR #4 (`oppa/security-payments-final`) then PR #5, and merge in that order.
- Provide `DATABASE_URL` to run integration tests.

## Session 2026-09-03 (second) — Risk & Abuse + wallet/payment money-safety (branch `codex/risk-wallet-money-readiness`, PR #6, rebased on PR #5)

SESSION STOP REASON: coherent money-safety batch verified and committed on a feature branch (owner requires no commits to main).

COMPLETED:
- Risk & Abuse deterministic engine (roadmap module 6, first version):
  - `database/migrations/0013_risk_wallet_safety.sql` — `oppa_risk_events`, `oppa_risk_decisions`, `oppa_wallet_limits`, `oppa_wallet_daily_counters` (+ RLS, indexes, fraud-analyst permission grants).
  - `apps/api/src/modules/risk/` — `RiskRepository` interface, `PostgresRiskRepository`, `RiskService` (validated event recording + active operator decisions), pure `transfer-limits` assessment.
- Wallet transfer limits enforced atomically: single / daily-total / daily-count limits checked inside the same transaction that moves money; daily counters incremented atomically with the transfer (serialized by the existing wallet row locks); audit event `wallet.transfer.created` written in-transaction.
- Operator decisions enforced server-side: `user`/`transfer` block fails transfers closed (`WALLET_TRANSFER_BLOCKED`, 409); `payment` block/review stops settlement before credit (`PAYMENT_RISK_BLOCKED` 403 / `PAYMENT_REQUIRES_REVIEW` 409).
- Payment risk now uses real counters: `PaymentRepository.countRecent` (24h paid/failed) replaces hardcoded zeros in webhook settlement (supersedes PR #4's `recentPaymentStats`).
- OTP abuse events recorded on cooldown / hourly-limit / attempts-exceeded paths (optional `RiskService` dependency, existing tests unaffected).
- Admin Control Center seed: `/admin/risk/decisions` GET+POST and `/admin/risk/events` GET behind `fraud.review` permission; admin router now mounted in `server.ts` under the protected router.
- Tests: 48 total, all passing. New: transfer-limits, risk-service, payment-risk, payment-service webhook settlement (operator block/review, real counters, webhook rejection), OTP abuse event.

FILES CHANGED (branch `codex/risk-wallet-money-readiness`, not main):
- `database/migrations/0013_risk_wallet_safety.sql` (new)
- `apps/api/src/modules/risk/` (new: risk-repository.ts, postgres-risk-repository.ts, risk-service.ts, transfer-limits.ts, transfer-limits.test.ts, risk-service.test.ts)
- `apps/api/src/modules/wallet/postgres-wallet-transfer-repository.ts`
- `apps/api/src/modules/payments/` (payment-service.ts, payment-repository.ts, postgres-payment-repository.ts, payment-service.test.ts, payment-risk.test.ts)
- `apps/api/src/modules/otp/otp-service.ts`, `otp-service.test.ts`
- `apps/api/src/modules/admin/admin-routes.ts`, `apps/api/src/http/error-handler.ts`, `apps/api/src/server.ts`
- `.github/workflows/api.yml` (full test suite), `docs/SECURITY.md`, `docs/API.md`, `CODEX_HANDOFF.md`

VERIFIED (executed in this session):
- test: PASS — `npm test` in `apps/api`: 48 pass, 0 fail, 5 skipped (Postgres integration tests; `DATABASE_URL` unset).
- typecheck: PASS — `npm run typecheck`.
- build: PASS — `npm run build`.
- diff: PASS — `git diff --check` (run before commit).

PARTIALLY COMPLETED:
- Registration-velocity, login-anomaly, device-anomaly, merchant-risk and spam signals are defined in the schema but not yet wired to auth/device flows (interface is extensible).
- Admin Control Center remains a seed (risk endpoints only); full console is a later roadmap module.
- Payment provider refund APIs still not integrated (reversal webhooks remain `501`); real-money refunds must not be advertised until wired.

NOT DONE:
- Notifications/Event Delivery (module 7), Admin/Control Center completion (8), Business (9), WhatsApp/Calls (10), Flutter/web surfaces (11), Operations/Launch QA (12).
- No Postgres-backed integration run in this environment (no `DATABASE_URL`); migrations 0012-0013 have not been applied anywhere.

KNOWN FAILURES/RISKS:
- Payment risk thresholds are the pre-existing main-branch policy (large amount alone does not block; block requires score >= 70). Threshold tuning is a product decision and should be reviewed before launch.
- Daily counters roll at UTC midnight; acceptable for v1, revisit for local-time zones.
- `bun.lock` untracked at repo root (environment artifact), intentionally not committed.

NEXT EXACT TASK:
- After PRs #4 and #5 merge, merge this branch (PR #6) — it stacks cleanly on top.

MANUAL OWNER ACTION:
- Review PRs #4 → #5 → #6 in order; merge after each is reviewed.
- Review payment-risk thresholds and wallet limit defaults (NGN 1M single / 5M daily / 50 count) before any real-money go-live.
- Provide `DATABASE_URL` so migrations 0001-0013 and integration tests can be executed.

The previous Security Core audit recorded:
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
