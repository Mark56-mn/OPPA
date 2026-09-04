# OPPA CODEX HANDOFF

## Purpose
Durable resume state for autonomous Codex sessions. The next agent must read this file together with `OPPA_MASTER_BUILD_SPEC.md`, `CODEX_AUTOPILOT.md` and `CODEX_BUILD_MAP.md`.

## LAST UPDATED
2026-09-04

## CURRENT BASELINE

Current main baseline before this documentation update:
- `024fb4f30b14f35589447b243be4becbb1988274` — merged Risk + Wallet money-safety (PR #6).
- `6372d0b23030b12cdb1e149fe199a942dcc4463e` — autonomous completion task added.

This handoff is now aligned to the current V1 scope and the product decision that WhatsApp is V2, not V1.

## IMPORTANT PRODUCT DECISION — LOCKED

**WhatsApp is excluded from OPPA V1.**

OPPA is not WhatsApp and is not affiliated with WhatsApp. Do not implement or expose WhatsApp API/Cloud API integration, WhatsApp account linking, WhatsApp Business onboarding, WhatsApp inbox/sync, WhatsApp-specific database models/routes/UI, WhatsApp Web automation/scraping, personal WhatsApp contact/message import or WhatsApp calls in V1.

The future V2 strategy is optional **OPPA Business external-channel integration** if officially authorized by Meta at that time. The purpose is to let eligible businesses use OPPA as their operating layer while optionally serving existing customers through authorized external channels. V2 must begin with fresh verification of current provider documentation, eligibility, permissions, policies, pricing and App Review requirements.

## CURRENT IMPLEMENTATION REALITY

The repository contains a substantial TypeScript API foundation:
- Auth/OTP/Identity
- SMS provider abstraction
- Device/Session/access tokens
- Profile/Contacts
- Messaging foundation
- Wallet/Ledger/Transfers
- Paystack/Flutterwave payment foundations
- Security Core
- Risk/Abuse
- Admin/RBAC foundation

### Security Core work merged into main

Security work includes intent-bound sensitive authorization, device-bound proofs, active-device checks, atomic challenge consumption, failure auditing and payment reversal authorization. Historical verification recorded 48 passing tests with 5 Postgres integration tests skipped because `DATABASE_URL` was unavailable, plus passing typecheck/build/diff checks. Re-run verification against current main before relying on historical results.

### Risk + money-safety work merged into main

Risk/Wallet work includes deterministic risk decisions, risk events, transfer limits, daily counters, operator blocks/review, payment recent counters and OTP abuse events. Admin risk endpoints were seeded behind permission checks.

Historical limitations still require closure:
- registration/login/device/merchant/spam anomaly signals may need wiring;
- Admin Control Center is not complete;
- Notifications/Event Delivery is incomplete;
- Business is incomplete;
- Flutter/web/admin/trust surfaces are incomplete;
- provider refunds/reconciliation are not production-complete;
- Postgres integration suite still requires a configured `DATABASE_URL` for execution.

## KNOWN BUSINESS SECURITY ISSUE

The previous agent identified that merchant self-ordering is currently allowed. Before Business is marked complete:
- merchant owner/staff must not create a normal customer order against its own business;
- enforce the rule server-side;
- prevent normal settlement/reward/fee abuse through self-ordering;
- add regression/adversarial tests.

## V1 EXECUTION ORDER

1. Auth + Identity closure
2. Device + Session closure
3. Messaging completion
4. Wallet closure
5. Payments closure
6. Security Core adversarial audit
7. Risk + Abuse completion/wiring
8. Notifications + Event Delivery
9. Admin / Control Center
10. Business / Merchant
11. OPPA-native Calls
12. Flutter mobile integration
13. Web/Admin/Trust surfaces
14. Operations + Launch QA

WhatsApp is not in this V1 order.

## NEXT EXACT TASK

Start by inspecting the current main repository and verify whether Auth/Identity, Device/Session, Messaging, Wallet, Payments, Security and Risk still have any incomplete gates. Fix the highest-priority V1 blocker found. Do not start WhatsApp.

If those foundations are sufficiently closed, proceed to **Notifications + Event Delivery**, then Admin, Business, Calls and the Flutter application in order.

## NOTIFICATIONS TARGET

Build provider-agnostic event/delivery infrastructure for security, login/device, messaging, wallet, payment, support and business events. Include in-app notifications, preferences, durable outbox/event semantics, idempotency, delivery status, retries/backoff and background processing. Never put OTPs, tokens, signatures or unnecessary sensitive financial/security information in notification payloads.

## BUSINESS TARGET

Build merchant onboarding/profile, staff roles, customers, products, orders, payments, merchant wallet/settlement boundaries, analytics and fraud/support controls. Keep merchant permissions separate from consumer wallet permissions. Enforce the self-ordering rule above.

## CALLS TARGET

Calls are OPPA-native, not WhatsApp. Build dedicated signaling/media/security architecture and do not claim external-platform calling support.

## FLUTTER TARGET

The mobile app must be a real V1 application connected to the API, not static mock screens. Required journey:

Onboarding → Phone → OTP → Profile → Theme → Home → Chats → Contacts → Wallet → Payments → Business → Connect → Me/Security

Use tokenized themes:
- Fluid Africa
- OPPA Pulse
- Everyday OPPA

## VERIFICATION RULE

For every module, inspect source/interfaces/migrations/routes/tests; implement the complete vertical slice; audit authentication, authorization, ownership, replay, idempotency, concurrency, abuse, error leakage and secrets; run available tests/typecheck/build/lint/schema checks; inspect the final diff; and update this handoff.

Never claim a test, migration, integration or deployment passed unless it was actually verified.

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

Owner performs merges manually. Do not spend credits on billing, CI/infrastructure or production credentials unless required for application correctness. Do not force merges or bypass security/quality gates.
