# OPPA — CURRENT BUILD MAP & CODEX EXECUTION PLAN

**Last reviewed:** 2026-09-02
**Repository:** `Mark56-mn/OPPA`
**Purpose:** concrete map of what exists, what must be verified, what remains, and how Codex must finish the application.

## 1. READ THESE FILES FIRST

Codex must read, in this order:

1. `OPPA_MASTER_BUILD_SPEC.md` — complete product/engineering specification.
2. `CODEX_AUTOPILOT.md` — non-negotiable autonomous build contract.
3. `CODEX_HANDOFF.md` — current session/resume state.
4. `CODEX_BUILD_MAP.md` — this operational map.
5. Relevant source, migrations, tests and deployment configuration.

The repository is the authority for implementation truth. Historical chat/file claims are context only. Re-run verification.

## 2. CURRENT REPOSITORY MAP

The repository currently has a TypeScript API foundation under `apps/api/src` with these modules:

```text
apps/api/src/
├── config/                  # environment/configuration
├── db/                      # PostgreSQL connection
├── http/                    # auth middleware, validation, request IDs, errors
├── modules/
│   ├── admin/               # admin routes + RBAC foundation
│   ├── auth/                # OTP auth orchestration/routes
│   ├── contact/             # contacts
│   ├── device/              # registered devices
│   ├── identity/            # phone identity
│   ├── messaging/           # conversations/messages foundation
│   ├── otp/                 # OTP generation/storage/verification controls
│   ├── payments/            # payment provider/settlement foundation
│   ├── profile/             # profile foundation
│   ├── security/            # device proof/step-up/security foundation
│   ├── session/             # access/refresh sessions
│   ├── sms/                 # provider abstraction + BulkSMS adapter
│   └── wallet/              # wallet/ledger/transfer foundation
└── server.ts
```

Other important repository areas include database migrations, API tests, `.github/workflows/api.yml`, `apps/api/package.json`, and `apps/api/.env.example`.

## 3. CURRENT IMPLEMENTATION STATUS

### Identity & Authentication — 🟡 FOUNDATION BUILT

Already represented in the codebase:
- phone OTP request/verification;
- OTP hashing, expiry and abuse controls;
- identity lookup/creation;
- device registration;
- sessions;
- signed bearer access tokens;
- refresh-session handling;
- authenticated middleware;
- server-side SMS provider adapter.

Still required before calling complete:
- full route-level integration verification;
- distinct device ID vs cryptographic public key model;
- logout/revocation/device management UX;
- account recovery;
- suspicious-login handling;
- PIN/biometric step-up UX and complete integration;
- adversarial/security coverage.

### Messaging — 🟡 BACKEND FOUNDATION

Foundation includes profiles, contacts, direct conversations, message sending, pagination and conversation authorization.

Still required:
- groups/roles;
- realtime delivery;
- delivery/read state;
- offline-first cache and reconnect sync;
- media/voice notes;
- push notifications;
- multi-device cryptographic state;
- mature reviewed E2EE implementation;
- block/report/search/deletion semantics;
- Flutter integration.

### Wallet — 🟡 FINANCIAL FOUNDATION

Foundation includes wallet persistence, ledger, atomic/idempotent mutations and authenticated transfer architecture.

Still required:
- complete transfer verification;
- limits;
- risk enforcement;
- step-up UX/integration;
- receive/request flows;
- funding flows;
- transaction UX;
- disputes/reconciliation;
- airtime/data/bills/merchant flows where supported.

Never expose arbitrary client-controlled credit/debit operations.

### Payments — 🟡 STRONG CORE, NOT PRODUCTION-COMPLETE

Foundation includes provider abstraction, Paystack/Flutterwave foundations, initialization, server verification, signed webhooks, idempotent settlement, risk boundary, payment history and atomic reversal state.

Still required:
- real provider refund API integration;
- refund/reversal webhook handling;
- provider reconciliation;
- final risk enforcement;
- adversarial financial tests;
- production provider certification/configuration.

Never enable real-money behavior solely because code compiles.

### Security Core — 🟡 FOUNDATION/AUDITED, CONTINUING

Foundation includes registered-device concepts, challenge/device proof, active-device checks, atomic challenge consumption, sensitive-operation authorization and fail-closed behavior.

Still required:
- complete security center UX;
- recovery/security alerts;
- broader adversarial coverage;
- complete integration across all sensitive actions;
- emergency controls.

### Risk & Abuse — 🔴 INCOMPLETE

Build deterministic, explainable controls for OTP abuse, registration velocity, login/device anomalies, transfer/payment velocity, repeated failures, takeover signals, merchant risk, spam and rate limits. Provide review/block states and audit trails.

### Notifications & Events — 🔴 INCOMPLETE

Build event abstraction, in-app notifications, push delivery, preferences, retries, idempotency, delivery state and durable background processing.

### Admin / Control Center — 🟡 FOUNDATION

RBAC/admin foundation exists. Complete:
- overview;
- users;
- messaging operational metadata;
- wallet/payments;
- businesses;
- WhatsApp;
- fraud/risk;
- security;
- support;
- devices/sessions;
- notifications/analytics;
- staff/roles;
- append-only audit viewer;
- emergency controls.

Least privilege is mandatory. Admins must not casually read private message contents.

### Business / Merchant — 🔴 INCOMPLETE

Build merchant onboarding, profiles, staff/roles, customers, products, orders, payments, settlements, analytics and merchant-specific fraud/support boundaries.

### WhatsApp / Calls — 🔴 INCOMPLETE

Implement only technically and contractually authorized integrations. Require consent, explicit scopes, disconnect/revoke, secure tokens, webhook verification and truthful capability descriptions. Calls require dedicated signaling/media/security architecture.

### Flutter Mobile UI — 🔴 NOT YET COMPLETE

Build the real mobile application against the real API, not static mock screens.

Required information architecture:

```text
Onboarding
Home
Chat / Groups / Contacts
Wallet / Send / Receive / Request / Fund / Transactions
Business
Connect
Me / Profile / OPPA ID / Appearance / Devices / Privacy / Security / Notifications / Support / Account
```

### Themes — 🔴 MUST BE INTEGRATED

One codebase and one functional system using theme tokens:
- Fluid Africa;
- OPPA Pulse;
- Everyday OPPA.

Theme changes visual tokens only. Users can change it at `Me → Appearance → OPPA Theme`.

### Web / Admin / Trust — 🔴 INCOMPLETE

Build the Vercel web surfaces, Control Center and Trust Center/legal/support pages required for launch.

### Operations — 🟡 DEPLOYMENT EXISTS, LAUNCH HARDENING REQUIRED

Intended architecture:

```text
Flutter + Web/Vercel
        ↓
Cloudflare DNS/edge/WAF
        ↓
Render API/workers/webhooks
        ↓
Supabase PostgreSQL
        ├── object storage/R2 as appropriate
        ├── BulkSMS Nigeria
        └── payment providers
```

Render deployment exists, but Codex must verify current production configuration rather than trusting historical deployment claims.

Still required:
- monitoring/alerts;
- queue/worker reliability;
- backups;
- disaster recovery;
- migration discipline;
- secret rotation;
- deployment verification;
- health/readiness checks;
- operational dashboards.

### Browser — 🔵 V1.5/LATER

In-app links/browser, safe browsing, tabs, history, bookmarks, downloads and privacy controls. Do not allow browser work to block V1 unless explicitly promoted by the master spec.

### VPN — 🔵 V2

Do not build a fake VPN. Only later implement a real Android VPN architecture with actual infrastructure, routing, bandwidth, privacy, abuse and monitoring controls.

### Mini Apps — 🔵 POST-V1

Architecture may anticipate them; implementation is deferred.

## 4. MANDATORY IMPLEMENTATION ORDER

Work continuously in coherent batches:

```text
1. Verify/close Auth & Identity
2. Complete Messaging
3. Close Wallet
4. Close Payments
5. Close Security Core
6. Build Risk & Abuse
7. Build Notifications/Event Delivery
8. Complete Admin/Control Center
9. Build Business/Merchant
10. Build authorized WhatsApp/Calls
11. Build Flutter mobile + web/admin integration
12. Operations + Launch QA
13. Browser (V1.5)
14. VPN (V2)
15. Mini Apps (post-V1)
```

Change order only when dependency analysis requires it, and record why in `CODEX_HANDOFF.md`.

## 5. EVERY MODULE MUST PASS THIS GATE

A module is **NOT DONE** until:

- implementation exists;
- database schema/migrations are correct;
- API/routes are wired;
- authorization is enforced;
- validation and failure paths are safe;
- idempotency/concurrency is addressed where applicable;
- audit events exist where required;
- tests cover happy, invalid, unauthorized and adversarial cases where relevant;
- typecheck/lint/build/tests pass;
- deployment compatibility is verified;
- no known critical bypass exists;
- documentation/handoff is updated.

## 6. PARALLEL WORK RULE

Parallelize independent analysis/test work when useful. Never concurrently write the same file. Before modifying a file, inspect its current version and preserve newer changes. Prefer small coherent commits.

## 7. SECURITY / FINANCIAL NON-NEGOTIABLES

- Server is authoritative.
- Never trust client balances, roles, payment success or security decisions.
- Financial mutations are atomic and concurrency-safe.
- Money uses integer minor units; never unsafe floating-point state.
- Sensitive operations require authentication + authorization + validation + security proof/step-up where required + risk + audit.
- Secrets never enter GitHub, Flutter bundles, logs, prompts or test fixtures.
- Never invent cryptography.
- Never fake external integrations.
- Fail closed when required security dependencies are unavailable.

## 8. CREDIT-EXHAUSTION / INTERRUPTION PROTOCOL

If Codex runs out of credits, context, execution time or environment capacity:

1. Stop starting new work.
2. Save all coherent changes.
3. Run the fastest meaningful verification available.
4. Commit coherent work.
5. Update `CODEX_HANDOFF.md` before stopping.
6. Report exactly what is complete and incomplete.

Use:

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
- lint: PASS/FAIL/NOT RUN

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

Do not claim completion for work that was not verified.

## 9. FINAL PRINCIPLE

**Finish the application, not the task list.** Continue until the V1 acceptance gate in `OPPA_MASTER_BUILD_SPEC.md` is satisfied. If a feature cannot safely or legally be implemented yet, implement the correct boundary, adapter, feature flag or explicit unavailable state and document the limitation instead of pretending it works.
