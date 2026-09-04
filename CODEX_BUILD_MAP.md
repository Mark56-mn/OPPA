# OPPA — CURRENT BUILD MAP & CODEX EXECUTION PLAN

**Last reviewed:** 2026-09-04
**Repository:** `Mark56-mn/OPPA`

## 1. READ FIRST

1. `OPPA_MASTER_BUILD_SPEC.md`
2. `CODEX_AUTOPILOT.md`
3. `CODEX_HANDOFF.md`
4. `CODEX_BUILD_MAP.md`
5. Actual source, migrations and tests for the active module

The repository is the implementation authority. Historical claims must be re-verified.

## 2. CURRENT FOUNDATION

The API under `apps/api/src` contains foundations for config/database/http, admin, auth/OTP, contacts, devices, identity, messaging, payments, profile, security, sessions, SMS and wallet. Database migrations and tests are present.

Recent main history includes:
- Security Core intent binding and sensitive-operation authorization (PR #5);
- Risk + Wallet money-safety (PR #6);
- autonomous completion task documentation.

## 3. CURRENT STATUS

| Module | Status | What remains |
|---|---|---|
| Auth/Identity | 🟡 foundation | closure, recovery, abuse/suspicious-login integration, full verification |
| Device/Session | 🟡 foundation | complete lifecycle UX, recovery and adversarial integration coverage |
| Messaging | 🟡 foundation | groups, realtime, delivery/read, offline sync, media, notifications, multi-device, mature E2EE only if truly implemented |
| Wallet | 🟡 strong foundation | complete user flows, funding/receive/request, reconciliation/disputes and full integration |
| Payments | 🟡 strong core | refunds/reconciliation, final risk integration and provider verification |
| Security | 🟡 strong foundation | final adversarial audit, security center/recovery/emergency integration |
| Risk/Abuse | 🟡 first version | wire registration/login/device/merchant/spam signals and operational review flows |
| Notifications/Events | 🔴 incomplete | event model, in-app, preferences, durable queue/retry/delivery |
| Admin/Control Center | 🟡 foundation | complete operational console and emergency/audit surfaces |
| Business/Merchant | 🔴 incomplete | onboarding, staff, customers, products, orders, payments, settlement, analytics, fraud/support |
| OPPA Calls | 🔴 incomplete | native voice/video signaling/media/security architecture and implementation |
| Flutter Mobile | 🔴 incomplete | real V1 application integrated with API |
| Web/Admin/Trust | 🔴 incomplete | required launch surfaces |
| Operations/Launch QA | 🟡 incomplete | production verification, monitoring, recovery, backups and release checks |
| WhatsApp | ⛔ V2 | explicitly excluded from V1 |
| Browser | 🔵 V1.5/later | deferred |
| VPN | 🔵 V2 | deferred |
| Mini Apps | 🔵 post-V1 | deferred |

## 4. LOCKED WHATSAPP DECISION

WhatsApp is **not part of OPPA V1**.

OPPA is not WhatsApp, is not affiliated with WhatsApp and must not make WhatsApp a runtime dependency.

Do not create V1:
- WhatsApp API/Cloud API integration;
- account linking;
- WhatsApp inbox/sync;
- WhatsApp database models/routes/UI;
- WhatsApp Web automation/scraping;
- personal WhatsApp message/contact import;
- WhatsApp calls.

V2 may later add an **optional OPPA Business external-channel integration** if Meta's current documentation, eligibility, policies, permissions and commercial terms support the intended capability. V2 work must begin with fresh provider verification.

## 5. REQUIRED EXECUTION ORDER

```text
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
13. Web/Admin/Trust
14. Operations + Launch QA
```

Do not start WhatsApp in this V1 sequence.

## 6. BUSINESS SAFETY REQUIREMENT

A merchant owner/staff account must not create an ordinary customer order against its own business. Enforce this server-side and add regression tests. Do not rely on the client to prevent it.

Consumer wallet permissions and merchant permissions must remain separate.

## 7. MODULE COMPLETION GATE

A module is done only when implementation, persistence/schema, route wiring, authorization, validation, safe failure handling, idempotency/concurrency where relevant, auditability, tests, typecheck/build and documentation are addressed. No known critical bypass may remain.

## 8. FINANCIAL RULES

- Server/database is authoritative.
- Client cannot declare payment success.
- Client cannot mutate balances.
- Money uses integer minor units.
- Financial mutations are atomic, idempotent and concurrency-safe.
- Sensitive transfers require authentication + authorization + validation + security proof/step-up + risk + audit as applicable.
- Never advertise provider refunds until provider APIs/webhooks are actually implemented.

## 9. SECURITY RULES

- Never invent cryptography.
- Never bypass device/session revocation.
- Never expose secrets.
- Never trust client roles, security decisions or financial state.
- Fail closed when required security dependencies are unavailable.
- Test replay, race, authorization and abuse boundaries.

## 10. SPEED / CREDIT RULE

Work autonomously in coherent batches. Parallelize independent inspection/test work, but never concurrently write the same file. Fix failures before unrelated expansion.

If credits/context/time run out:
- stop starting new work;
- save coherent work;
- verify what can be verified;
- commit coherent work;
- update `CODEX_HANDOFF.md` with exact state, files, commits, verification, risks and next task.

## 11. FINAL TARGET

V1 must support a genuine end-to-end path from install/onboarding/phone verification through profile/theme/home, contacts, messaging, offline/reconnect, notifications, wallet, secure transfers, funding/payment, history, V1 business/customer functionality, security/devices/recovery and support/reporting, with required operations/RBAC/audit/emergency controls.
