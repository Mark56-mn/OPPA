# OPPA CODEX HANDOFF

## Purpose
Durable resume state for autonomous Codex sessions. The next agent must read this file together with `OPPA_MASTER_BUILD_SPEC.md`, `CODEX_AUTOPILOT.md` and `CODEX_BUILD_MAP.md`.

## LAST UPDATED
2026-09-04 (session: notifications, business, admin emergency, messaging receipts implemented and verified)

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

## SESSION 2026-09-04 — COMPLETED WORK (uncommitted at session end)

### Verified baseline
- `bun run api:typecheck` PASS; `bun test src` (apps/api) 85 pass / 5 skip / 0 fail. The 5 skips are Postgres integration tests requiring `DATABASE_URL` (unchanged limitation).
- Prior-session uncommitted work was reviewed, fixed and kept: account surface (`/v1/account`), auth security events, session crypto HMAC pepper hardening, payment history via repository.

### Implemented this session (all uncommitted — owner merges manually)
1. **Messaging completion** (migration 0014 wired): per-member delivery/read receipts, mark-read (self receipts only), per-message receipts, edit/delete with ownership checks, unread counts; group conversations (create/add-member with owner-admin gating/leave); routes under `/v1/conversations` and `/v1`; tests in `src/modules/messaging/messaging.test.ts`.
2. **Notifications + Event Delivery** (migration 0015 wired): durable outbox with dedupe keys, SKIP LOCKED worker claiming, in-app delivery, preferences, exponential backoff (30s→480s), staff-gated `/v1/notifications/process`, background worker in `server.ts` (60s, unref). Transactional outbox hooks: wallet transfer (sender+receiver), payment settlement, business orders. Tests: `src/modules/notifications/notifications.test.ts`.
3. **Business/Merchant** (migration 0016 wired): businesses/staff/products/orders/analytics; customer wallet→owner wallet settlement atomically with ledger entries; **self-ordering blocker enforced server-side in `createOrder`** (any staff row on the business disqualifies the caller) — test `merchant staff cannot create a customer order against their own business`. Routes under `/v1/business`. Tests: `src/modules/business/business.test.ts`.
4. **Admin/Control Center** (migration 0017 wired): emergency actions (freeze/unfreeze user, revoke all sessions, suspend/restore business) requiring `emergency.execute` permission + reason 5-500 chars + `confirm:"CONFIRM"` + self-targeting prevention + append-only audit + emergency_actions record; audit/security-events/users(masked phones) views. Routes under `/v1/admin`. Tests: `src/modules/admin/admin-emergency.test.ts`.
5. Housekeeping: duplicate `revokeDevice` repository method consolidated into existing `revoke`; removed stale `message-lifecycle.ts` interface file; new error codes mapped in `http/error-handler.ts`; `package.json` test glob quoted so `bun test` doesn't pick up `dist/`.

### Verification evidence (executed this session)
- test: PASS (85 pass / 5 skip / 0 fail, `bun test src` in apps/api)
- typecheck: PASS (`bun run api:typecheck`)
- build: PASS (`bun run build`, dist/server.js emitted; dist removed after verification to keep tree clean)
- diff audit: no TODOs/stubs/501 paths, no WhatsApp references, no hard-coded secrets in apps/api/src or database/

### Known limitations (not regressions)
- Postgres integration suite still requires `DATABASE_URL`; migrations 0014-0017 not executed against a live database this session. Run them before deploy.
- Notifications are in-app only (per V1 plan); external provider adapters are a later milestone.
- `/v1/notifications/process` requires the `notifications.read` staff permission (granted by migration 0017 to admin/super_admin roles).

## NEXT EXACT TASK

1. Commit the coherent uncommitted work above (owner merge policy applies).
2. Apply migrations 0014-0017 on a Postgres instance with `DATABASE_URL` set and re-run the full suite including integration tests.
3. Continue V1 execution order: **OPPA-native Calls** (signaling/media/security architecture), then **Flutter mobile integration**, then Web/Admin/Trust surfaces, then Operations + Launch QA.
4. Do not start WhatsApp (V2).

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
