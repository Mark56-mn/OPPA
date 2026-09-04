# OPPA CODEX HANDOFF

## Purpose
Durable resume state for autonomous Codex sessions. The next agent must read this file together with `OPPA_MASTER_BUILD_SPEC.md`, `CODEX_AUTOPILOT.md`, `CODEX_BUILD_MAP.md`, and `CODEX_BACKEND_ADVERSARIAL_AUDIT_TASK.md`.

## LAST UPDATED
2026-09-04 — backend V1 adversarial audit task queued as the exact next execution step.

## CURRENT BASELINE

Known main baseline before this documentation/task update:
- `6dd97304fe7a7f5481a81b5aaff488cc42384451` — latest known application milestone.
- `62078eeab719bd8e13e981c7871e52c9d295d137` — added `CODEX_BACKEND_ADVERSARIAL_AUDIT_TASK.md`.

Owner merges application work manually. Do not spend credits on CI, billing or production infrastructure.

## IMPORTANT PRODUCT DECISION — LOCKED

**WhatsApp is excluded from OPPA V1.**

OPPA is not WhatsApp and is not affiliated with WhatsApp. Do not implement or expose WhatsApp API/Cloud API integration, WhatsApp account linking, WhatsApp Business onboarding, WhatsApp inbox/sync, WhatsApp-specific database models/routes/UI, WhatsApp Web automation/scraping, personal WhatsApp contact/message import or WhatsApp calls in V1.

Future V2 may consider authorized OPPA Business external-channel integrations after fresh verification of provider documentation, eligibility, permissions, policies, pricing and App Review requirements.

## CURRENT IMPLEMENTATION REALITY

The repository contains a substantial TypeScript API foundation including:
- Auth/OTP/Identity
- SMS provider abstraction
- Device/Session/access tokens
- Profile/Contacts
- Messaging
- Wallet/Ledger/Transfers
- Paystack/Flutterwave payment foundations
- Security Core
- Risk/Abuse
- Notifications/Event Delivery
- Business/Merchant
- Admin/RBAC/Emergency Controls

Latest application milestone included messaging receipts/groups/edit-delete/unread counts, durable notifications outbox/in-app delivery, merchant/business/orders/settlement with server-side self-order blocking, and admin emergency controls/audit.

Historical verification had 85 passing tests and 5 Postgres integration skips because `DATABASE_URL` was unavailable. These results must be re-run on current source; never treat historical output as current proof.

Known limitations include real Postgres migration/integration verification when no `DATABASE_URL` is available, plus any provider refund/reconciliation gaps that the adversarial audit confirms remain.

## EXACT NEXT TASK

**Run `CODEX_BACKEND_ADVERSARIAL_AUDIT_TASK.md` from the current main baseline.**

The next agent must:

1. Inspect the actual current repository rather than trusting prior summaries.
2. Audit migrations/schema, authentication, identity, sessions, devices, Security Core, wallet/ledger, payments, messaging, notifications/outbox, business/merchant, admin/RBAC, risk/abuse and every API route.
3. Specifically hunt for IDOR/BOLA, privilege escalation, replay, race conditions, duplicate settlement, double debit/credit, authorization gaps, cross-tenant access, enumeration, information leakage and unsafe error handling.
4. Verify migrations 0014–0017 against real Postgres if `DATABASE_URL` is available.
5. Fix every real in-scope defect found and add regression/adversarial tests.
6. Run tests, typecheck, build and all other locally available verification.
7. Update this handoff with exact findings, fixes, files, commits, verification and the next exact task.

Do **not** start Calls, Flutter, WhatsApp, frontend, CI or infrastructure during this task.

## V1 EXECUTION ORDER AFTER AUDIT

1. Backend adversarial audit + integration closure **← CURRENT**
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
