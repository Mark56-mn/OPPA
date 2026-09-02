# OPPA — MASTER APPLICATION BUILD SPECIFICATION

**Document purpose:** durable product + engineering source of truth for autonomous Codex implementation.
**Status:** active master plan.
**Last reviewed:** 2026-09-02.
**Repository:** `Mark56-mn/OPPA`.

---

## 0. EXECUTIVE DIRECTIVE

Build the **complete OPPA application**, not a demo, mockup, disconnected collection of screens, or backend-only prototype.

OPPA is a mobile-first African communications and financial platform combining:

- phone-first identity and authentication;
- private messaging and contacts;
- groups, media, realtime delivery and offline synchronization;
- wallet and peer-to-peer transfers;
- payment-provider integrations;
- business/merchant capabilities;
- notifications and support;
- device/security controls;
- WhatsApp-connected capabilities only where technically and contractually authorized;
- OPPA Connect / in-app browsing;
- an operations/admin Control Center;
- a coherent Flutter mobile experience plus web/admin surfaces where required.

**Codex must continue autonomously through the roadmap. Do not stop for user confirmation between normal implementation steps.**

If a feature is not safe or legally/technically supportable yet, implement the correct architecture, interface, feature flag or explicit unavailable state rather than faking functionality.

---

# 1. CURRENT REPOSITORY STATE — DO NOT REBUILD FROM ZERO

The repository already contains a backend foundation. The current `main` tree includes:

```text
apps/api/src/
  config/
  db/
  http/
  modules/
    admin/
    auth/
    contact/
    device/
    identity/
    messaging/
    otp/
    payments/
    profile/
    security/
    session/
    sms/
    wallet/
  server.ts
```

There are also database migrations, documentation and Codex operating files.

Existing work documented/audited before this specification includes:

- phone OTP authentication;
- OTP hashing, expiry, attempt/request controls;
- BulkSMS provider adapter foundation;
- identity creation/lookup;
- device registration;
- sessions, refresh sessions and bearer access tokens;
- profile and contact foundations;
- direct conversation and message APIs with pagination/authorization;
- wallet schema, ledger and atomic/idempotent transfer foundation;
- payment provider abstraction with Paystack/Flutterwave foundations;
- payment verification/webhook handling and wallet settlement safeguards;
- payment reversal state/atomic reversal boundary;
- admin/RBAC foundations;
- Security Core including step-up challenges, active-device validation, device-bound proofs and sensitive-operation authorization.

The latest durable handoff also records successful API tests, typecheck, build and diff checks for the Security Core audit. **Codex must independently re-run checks against the current repository and must not trust historical claims.**

---

# 2. IMPORTANT: CURRENT STATE VS TARGET STATE

Existing files/modules are **not proof of completion**. A module is complete only when implementation, wiring, persistence, authorization, failure handling, tests and build/deployment compatibility are verified.

Treat the following status as the starting map, not as permission to skip verification.

| Area | Starting state | Target |
|---|---|---|
| Identity/Auth | 🟡 foundation built | production-complete auth/recovery/device UX |
| Messaging | 🟡 backend foundation | full secure messenger |
| Wallet | 🟡 ledger/transfer foundation | complete wallet product |
| Payments | 🟡 strong core | reconciliation/refunds/tests/production readiness |
| Security | 🟡 core implemented and audited | complete security center + adversarial coverage |
| Risk/Abuse | 🔴 incomplete | operational risk engine |
| Notifications | 🔴 incomplete | event + push/in-app delivery |
| Admin | 🟡 RBAC/foundation | complete Control Center |
| Business | 🔴 incomplete | merchant product |
| WhatsApp | 🔴 incomplete | authorized connector only |
| Calls | 🔴 incomplete | voice/video architecture + implementation |
| Browser | 🔵 planned | V1.5/later unless required for launch |
| VPN | 🔵 future | V2, not V1 |
| Mini Apps | 🔵 future | post-V1 |
| Mobile UI | 🔴 must be built/integrated | complete Flutter app |
| Web/Admin UI | 🔴 must be built/integrated | production web/control surfaces |
| Operations | 🟡 deployment exists | monitoring, backups, recovery, launch readiness |
| Legal/Trust | 🟡 architecture/docs planned | launch-appropriate trust center |

---

# 3. PRODUCT INFORMATION ARCHITECTURE

## Mobile app

### Onboarding
1. OPPA Pulse logo/splash.
2. Phone number.
3. OTP verification.
4. Profile/name creation.
5. Optional voice-assisted name entry where appropriate.
6. Choose OPPA look/theme.
7. Permissions and privacy explanations.
8. Home.

### Main experience

```text
OPPA
├── Home
│   ├── Chats
│   ├── Contacts
│   ├── Wallet snapshot
│   ├── Notifications
│   └── Quick actions
├── Chat
│   ├── Direct messages
│   ├── Groups
│   ├── Media
│   ├── Voice notes
│   ├── Search
│   └── Contact/profile
├── Wallet
│   ├── Balance
│   ├── Send
│   ├── Receive
│   ├── Request
│   ├── Fund wallet
│   ├── Transactions
│   ├── Airtime
│   ├── Data
│   ├── Bills (where supported)
│   └── Wallet settings
├── Business
│   ├── Inbox
│   ├── Customers
│   ├── Products
│   ├── Orders
│   ├── Payments
│   └── Analytics
├── Connect
│   ├── In-app links/browser
│   ├── Privacy browsing controls
│   └── VPN (future)
└── Me
    ├── Profile
    ├── OPPA ID
    ├── Appearance
    ├── Devices
    ├── Privacy
    ├── Security
    ├── Notifications
    ├── Wallet settings
    ├── Help & Support
    └── Account
```

---

# 4. THEME SYSTEM — ONE APP, THREE EXPERIENCES

Implement a **theme-token architecture**, not three duplicated apps.

Starting themes:

1. **Fluid Africa** — warm, expressive, culturally inspired.
2. **OPPA Pulse** — futuristic, dark, energetic; official OPPA logo/brand direction.
3. **Everyday OPPA** — clean, lightweight, practical.

The user's theme changes visual tokens only. Account, chats, wallet, contacts, security and functionality remain the same.

Theme must be changeable later under:

`Me → Appearance → OPPA Theme`

The architecture should support future customization tokens such as:

- chat bubble style;
- wallpaper;
- accent;
- dark/light mode;
- animation intensity;
- Pulse animation;
- chat density;
- font size;
- data-saving mode.

Do not hard-code theme-specific business logic.

---

# 5. AUTH + IDENTITY

Complete and verify:

- phone OTP request/verify;
- secure OTP generation and hashing;
- expiry and attempt limits;
- request throttling/rate limiting;
- anti-enumeration behavior;
- identity creation/lookup;
- device registration;
- distinct `deviceId` and cryptographic device public key concepts;
- session creation;
- short-lived access tokens;
- refresh-token rotation/revocation;
- logout/revoke-device;
- account recovery;
- suspicious-login signals;
- PIN/biometric step-up for high-risk actions.

OTP provider architecture must remain replaceable:

```text
SMS Gateway
├── BulkSMS Nigeria (primary initial provider)
├── Termii (replaceable/fallback)
└── future providers
```

Secrets stay server-side. Never place SMS/payment credentials in Flutter, GitHub, logs or prompts.

---

# 6. MESSAGING

Build toward a real messenger, not a REST chat demo.

Required:

- profiles;
- contacts;
- direct conversations;
- groups and membership/roles;
- message persistence;
- pagination/cursors;
- realtime delivery;
- delivery/read state;
- offline-first local cache;
- sync/reconciliation after reconnect;
- media attachments;
- voice notes;
- message search;
- block/report flows;
- push notifications;
- multi-device support;
- deletion/edit semantics where specified.

### Encryption

Use established, reviewed cryptographic protocols/libraries. **Never invent a custom encryption protocol.**

Separate:

- identity/device keys;
- message encryption state;
- server-stored ciphertext/metadata;
- key changes;
- recovery/backup semantics.

Do not claim E2EE until the implementation actually provides the promised properties and has appropriate testing/review.

---

# 7. WALLET + MONEY MOVEMENT

The server/database is authoritative.

Use integer minor units for money. Never use unsafe JavaScript floating-point arithmetic for monetary state.

Required:

- wallet account;
- balance retrieval;
- double-entry/ledger records;
- atomic credit/debit primitives restricted to trusted internal paths;
- authenticated transfer;
- recipient validation;
- self-transfer prevention;
- strict amount/reference validation;
- idempotency;
- reference mismatch rejection;
- deterministic wallet locking;
- concurrency safety;
- insufficient-funds protection;
- transaction history/pagination;
- transfer limits;
- risk checks;
- audit events;
- step-up authorization for sensitive transfers;
- reconciliation support;
- disputes and support references.

Never expose arbitrary client-controlled credit/debit endpoints.

For user confirmation, show amount, fee, total, recipient and resulting balance before committing when applicable.

---

# 8. PAYMENTS

Use a provider abstraction so OPPA is not locked to one provider.

```text
PaymentProvider
├── initializePayment()
├── verifyPayment()
└── verifyWebhook()

Providers
├── Paystack
└── Flutterwave
```

Required:

- payment initialization;
- server-side verification;
- raw-body webhook signature verification;
- amount/currency validation;
- idempotent settlement;
- wallet credit only after verified provider evidence;
- risk decision before settlement;
- payment history;
- atomic reversal state;
- provider refund API integration before real refunds are advertised;
- refund/reversal webhooks;
- provider reconciliation;
- adversarial tests;
- audit events.

**The client never declares a payment successful.**

Do not enable real-money production behavior merely because the code compiles.

---

# 9. SECURITY CORE

Security is a cross-cutting platform, not a page.

Required:

- registered device identity;
- cryptographic device public keys;
- challenge/response proof;
- active-device checks;
- atomic challenge consumption;
- step-up authentication;
- sensitive-operation authorization;
- security event log;
- security alerts;
- active sessions/devices UI;
- remote device revocation;
- recovery flows;
- wallet/payment sensitive-operation protection;
- emergency controls;
- fail-closed behavior when security dependencies are unavailable.

Sensitive flow:

```text
Request
→ authentication
→ authorization
→ validation
→ device/security proof
→ risk decision
→ business transaction
→ audit event
→ response
```

Never weaken security to make a test pass.

---

# 10. RISK & ABUSE

Implement a deterministic, explainable first version with an extensible interface.

Cover:

- OTP abuse;
- registration velocity;
- login anomalies;
- device anomalies;
- transfer velocity;
- payment anomalies;
- repeated failures;
- account takeover signals;
- merchant risk;
- spam/abuse signals;
- rate limits;
- review/block decisions;
- audit trail.

Risk should fail safely. Avoid irreversible automatic decisions where evidence is weak; support review states.

---

# 11. NOTIFICATIONS + EVENTS

Build an internal event model and delivery abstraction.

Events should cover:

- security alerts;
- new login/device;
- message notifications;
- payment status;
- wallet transfers;
- support updates;
- business/order events.

Required:

- in-app notifications;
- notification preferences;
- retry handling;
- idempotency;
- delivery status;
- background jobs/queue;
- provider failure handling.

---

# 12. ADMIN / OPPA CONTROL CENTER

Build a proper operations console with least privilege.

```text
Control Center
├── Overview
├── Users
├── Messaging
├── Wallet & Transactions
├── Payments
├── Businesses
├── WhatsApp
├── Risk & Fraud
├── Security
├── Support
├── Devices & Sessions
├── Notifications
├── Analytics
├── Staff & Roles
├── Audit
└── Emergency Controls
```

Roles should be separated (for example super admin, operations, finance, security, support, developer, auditor).

Admins must not casually access private message contents. Prefer technical metadata and tightly controlled, explicitly justified access paths.

### Audit

Audit events should cover:

- account changes;
- device/session actions;
- security events;
- wallet/payment operations;
- staff/role changes;
- emergency actions.

Implement append-only semantics and restricted audit access.

### Emergency Center

Potential controls:

- pause wallet transfers;
- pause registrations;
- disable a connector;
- pause merchant payments;
- maintenance mode.

Require strong authorization, explicit confirmation, reason capture and audit. Use dual approval for the most consequential controls when appropriate.

---

# 13. BUSINESS / MERCHANT PLATFORM

Build:

- merchant profiles;
- business onboarding;
- merchant staff/roles;
- customer management;
- product catalog;
- orders;
- payments;
- merchant wallet/settlement boundaries;
- analytics;
- customer support;
- fraud controls.

Do not mix consumer wallet permissions with merchant permissions.

---

# 14. WHATSAPP + CALLS

Only implement integrations that are technically and contractually authorized.

For any WhatsApp-connected feature:

- clear consent screen;
- explicit scope of access;
- clear explanation of what OPPA can/cannot access;
- disconnect/revoke;
- provider abstraction;
- secure credentials/tokens;
- webhook verification;
- audit events;
- no claims that exceed the actual integration.

Do not invent or implement unsupported multi-device behavior by bypassing platform controls.

Calls should have a dedicated architecture for signaling, permissions, media transport and security rather than being bolted onto chat.

---

# 15. OPPA CONNECT / BROWSER / VPN

### Browser

Planned V1.5/later unless a launch requirement changes it:

- in-app link handling;
- trusted OPPA content;
- safe external browsing;
- tabs;
- history;
- bookmarks;
- downloads;
- privacy controls;
- external-open option.

Prefer secure platform browser components where appropriate. Keep Safe Browsing enabled and do not expose unsafe native bridges.

### VPN

**V2 only. Do not build a fake VPN.**

If later implemented, it must use Android's proper VPN APIs and have real infrastructure, routing, bandwidth, privacy, abuse and monitoring design.

---

# 16. OFFLINE-FIRST / AFRICAN NETWORK REALITY

Design for unreliable mobile networks and constrained devices.

Required principles:

- local cache for appropriate data;
- optimistic UI only where safe;
- durable outbound queue;
- sync on reconnect;
- retry with backoff;
- idempotent mutations;
- compact payloads;
- image/media optimization;
- data-saving mode;
- clear pending/failed states.

Never apply optimistic assumptions to final financial settlement.

---

# 17. INFRASTRUCTURE

Initial architecture:

```text
Flutter Mobile App ─┐
                    ├── Cloudflare edge/DNS/WAF
Web Frontend ───────┘
                           │
                           ▼
                     Render API/worker
                           │
             ┌─────────────┼─────────────┐
             ▼             ▼             ▼
       Supabase PG     Object Storage   Providers
                         R2/Storage     SMS/Payments
```

Current intended responsibilities:

- **Vercel:** web frontend and web surfaces.
- **Render:** core API/workers/webhooks.
- **Supabase:** PostgreSQL and appropriate supporting services.
- **Cloudflare:** DNS, edge protection, WAF/rate limiting as appropriate, future R2/edge services.
- **BulkSMS Nigeria:** initial Nigerian OTP/SMS provider behind an adapter.
- **GitHub:** source control.

RunCode.io, if used, is a development/build workshop, **not automatically production infrastructure**.

Production secrets must be configured through secret managers/environment configuration, never committed.

---

# 18. WEB + TRUST CENTER

Build web surfaces for:

- OPPA landing site;
- Trust Center;
- support/help;
- legal documents;
- status/operational notices;
- admin console where appropriate.

Trust documentation should distinguish:

- message privacy architecture;
- transaction/financial records;
- account/service data;
- third-party providers.

Required document architecture before relevant launches:

- Terms of Service;
- Privacy Policy;
- Acceptable Use Policy;
- Community Guidelines;
- Security Overview;
- Account Deletion Policy;
- Support/Complaint Policy;
- FAQ;
- Wallet/Payment Terms;
- Refund/Dispute Policy;
- financial partner disclosure;
- Business Terms;
- WhatsApp Connection Terms only after the actual integration is finalized;
- data retention/deletion disclosures;
- third-party services disclosure;
- security vulnerability disclosure.

Legal/compliance text must not falsely describe OPPA as a bank, licensed payment institution or other regulated entity unless that status actually exists.

---

# 19. DOMAIN / SERVICE NAMING

Existing intended structure:

```text
oppa-technologies.online
├── web/frontend
├── app.oppa-technologies.online   (if used)
├── api.oppa-technologies.online   → Render
├── admin.oppa-technologies.online → admin surface
└── company email on root domain
```

Do not put application secrets in DNS. Keep API/payment/SMS credentials in server-side secrets.

---

# 20. ENGINEERING QUALITY GATES

Every module must pass the following before being marked complete:

1. Code exists and is actually wired into the application.
2. Database schema/migrations match runtime repositories.
3. Authentication is enforced where required.
4. Authorization is enforced server-side.
5. Input validation is strict.
6. Failure paths are explicit and safe.
7. Idempotency exists for retryable mutations.
8. Concurrency is safe where state can race.
9. Audit events exist for sensitive actions.
10. Tests cover success, invalid input and authorization failures.
11. Adversarial/replay/concurrency tests exist where applicable.
12. Typecheck/build passes when executable.
13. Deployment configuration remains compatible.
14. No secrets are exposed.
15. No known critical security bypass remains.
16. Documentation/handoff is updated.

**Do not use “file exists” as a definition of done.**

---

# 21. AUTONOMOUS CODex EXECUTION PROTOCOL

When Codex starts:

### Step A — Recon

- inspect `git status`;
- inspect current branch and recent commits;
- inspect repository tree;
- read `CODEX_AUTOPILOT.md`;
- read this file;
- read `CODEX_HANDOFF.md`;
- inspect the actual current implementation of the active module.

### Step B — Plan

Create a concise internal checklist for the active module.

Group independent work so it can be performed efficiently, but **never concurrently write the same file** or overwrite newer changes.

### Step C — Implement

Implement the largest coherent safe batch possible.

Reuse existing abstractions. Do not duplicate services that already exist.

### Step D — Verify

Run the repository's available:

- tests;
- typecheck;
- build;
- lint/static checks where configured;
- migration/schema checks;
- targeted integration/adversarial checks.

Fix failures before moving to unrelated work.

### Step E — Audit

After each major module:

- inspect the diff;
- inspect security boundaries;
- inspect data flow;
- inspect authorization;
- inspect migrations;
- inspect dependency changes;
- inspect error handling;
- inspect secrets/configuration.

### Step F — Continue

If the active module passes its gate, immediately continue to the next unfinished module. Do not wait for user confirmation.

Recommended order:

```text
1 Auth/Identity closure
2 Messaging completion
3 Wallet closure
4 Payments closure
5 Security Core closure
6 Risk & Abuse
7 Notifications/Event Delivery
8 Admin/Control Center
9 Business
10 WhatsApp/Calls
11 Mobile/Web integration
12 Operations/Launch QA
13 Browser (V1.5)
14 VPN (V2)
15 Mini Apps (post-V1)
```

If dependencies make a different order safer, explain the dependency in the handoff and proceed with the closest safe module.

---

# 22. CREDIT / SESSION EXHAUSTION PROTOCOL — CRITICAL

**Codex must never hide partial completion because credits run out.**

If credits, context, execution time or environment limits are exhausted:

1. Stop starting new work.
2. Save all completed changes.
3. Run the fastest meaningful verification available.
4. Commit completed work if the repository is in a coherent state.
5. Update `CODEX_HANDOFF.md` immediately.
6. Clearly record:
   - what was completed;
   - what files changed;
   - commit SHA(s);
   - tests/build/typecheck actually run and exact results;
   - what is partially implemented;
   - what remains undone;
   - known failures;
   - security concerns;
   - exact next task;
   - any manual action required from the owner.
7. **Never say “complete” for work that was not verified.**

Use this status format:

```text
SESSION STOP REASON: credits/time/environment

COMPLETED:
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

This requirement is mandatory because another Codex session must be able to resume without guessing.

---

# 23. ANTI-HALLUCINATION / ANTI-FAKE COMPLETION RULES

Codex must not:

- claim a deployment is live without checking it;
- claim a webhook works without exercising/verifying it;
- claim a payment provider is production-ready without configuration and tests;
- claim E2EE exists merely because encryption-related files exist;
- claim a mobile app works merely because backend tests pass;
- claim a database migration is applied without evidence;
- claim an external integration works without real verification;
- replace real integrations with hidden simulations;
- commit credentials or API keys;
- silently downgrade security controls;
- overwrite newer repository work to resolve a conflict.

When an external dependency is unavailable, create a clean adapter/interface and explicit configuration boundary, then record the limitation.

---

# 24. DEFINITION OF COMPLETE OPPA V1

OPPA V1 is complete only when the user can install/use the mobile application and the major product paths are genuinely connected:

```text
Install
→ onboarding
→ phone verification
→ profile
→ choose theme
→ home
→ contacts
→ direct/group chat
→ offline/reconnect behavior
→ notifications
→ wallet
→ secure transfer
→ wallet funding/payment
→ transaction history
→ business/customer path where included in V1
→ security/devices/recovery
→ support/reporting
```

And operations can safely run the service through the Control Center with RBAC, audit and emergency controls.

A feature may be explicitly deferred if it is marked **V1.5/V2** in this document and the product still meets its V1 definition.

---

# 25. FINAL DIRECTIVE TO CODEX

**Build the application completely and continuously from the current repository state.**

Do not restart the project.
Do not throw away working foundations.
Do not wait for permission after every task.
Do not fake unfinished capabilities.
Do not compromise security for speed.
Do optimize execution for speed by working in coherent batches and reusing existing code.

When you finish one verified module, move to the next.
When credits run out, leave a truthful, precise handoff.
When the entire V1 definition is satisfied and verified, prepare the repository for release rather than inventing more scope.

**The repository is the implementation. This document is the product/build map. CODEX_AUTOPILOT.md is the operating contract. CODEX_HANDOFF.md is the durable session state.**
