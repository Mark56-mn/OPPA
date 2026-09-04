# OPPA — MASTER APPLICATION BUILD SPECIFICATION

**Status:** ACTIVE V1 MASTER SPEC
**Last reviewed:** 2026-09-04
**Repository:** `Mark56-mn/OPPA`

## 0. PRODUCT DIRECTIVE

Build the complete OPPA V1 application from the current repository state. OPPA is a mobile-first African communications, identity, wallet, payments, business and security platform. It is not a WhatsApp clone and is not affiliated with WhatsApp.

The repository is the implementation source of truth. Existing files do not prove completion. Every module must be inspected, wired, tested and audited before it is marked complete.

## 1. V1 SCOPE — LOCKED

V1 includes:
- phone-first identity and OTP authentication;
- device and session security;
- profiles and contacts;
- direct and group messaging;
- appropriate media/voice-note support;
- realtime delivery;
- offline-first synchronization;
- notifications/event delivery;
- wallet and peer-to-peer transfers;
- payment-provider integrations and verified settlement;
- risk/abuse controls;
- business/merchant capabilities included in the V1 product path;
- OPPA-native voice/video calls where safely implementable;
- support/reporting;
- security center and recovery;
- Flutter mobile application;
- required web/admin/trust surfaces;
- operations/launch readiness.

### Explicitly NOT V1
- WhatsApp integration of any kind;
- WhatsApp account linking;
- WhatsApp Business API/Cloud API runtime integration;
- WhatsApp inbox or message synchronization;
- WhatsApp-specific database models/routes/UI;
- WhatsApp Web automation or scraping;
- personal WhatsApp contact/message import;
- WhatsApp calls;
- VPN;
- Mini Apps;
- Browser expansion beyond what is strictly necessary for V1.

### WhatsApp is V2

WhatsApp is a **future optional OPPA Business external-channel integration**, not a core OPPA dependency. The future objective is to let eligible businesses use OPPA as their business operating layer while optionally communicating with customers through officially authorized WhatsApp Business capabilities. That work belongs to V2 and must not consume V1 implementation scope.

When V2 begins, provider-specific capabilities must be verified against current Meta documentation, eligibility, permissions, policies, pricing and App Review requirements before implementation. Never build an unofficial connector.

## 2. CURRENT BACKEND FOUNDATION

The current API contains foundations for:
- config/database/http;
- auth/OTP/identity;
- SMS provider abstraction;
- devices/sessions/access tokens;
- profile/contacts;
- messaging;
- wallet/ledger/transfers;
- payments/Paystack/Flutterwave foundations;
- security/step-up/device proof/intent binding;
- risk/abuse;
- admin/RBAC.

Recent main-branch work includes Security Core intent binding and Risk + Wallet money-safety. Historical test results must be re-run against the current repository before being relied upon.

## 3. PRODUCT INFORMATION ARCHITECTURE

```text
OPPA Mobile
├── Onboarding
│   ├── Splash
│   ├── Phone
│   ├── OTP
│   ├── Profile
│   ├── Theme
│   └── Permissions
├── Home
│   ├── Chats
│   ├── Contacts
│   ├── Wallet snapshot
│   ├── Notifications
│   └── Quick actions
├── Chat
│   ├── Direct
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
│   ├── Fund
│   ├── Transactions
│   └── Supported bill/airtime/data paths
├── Business
│   ├── Profile
│   ├── Customers
│   ├── Products
│   ├── Orders
│   ├── Payments
│   ├── Staff
│   └── Analytics
├── Connect
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

## 4. THREE-THEME SYSTEM

Use one codebase and one functional system with tokens:
1. Fluid Africa
2. OPPA Pulse
3. Everyday OPPA

Theme changes visual tokens only. Never duplicate business logic, security logic or data models per theme. Theme selection/change belongs under `Me → Appearance → OPPA Theme`.

## 5. AUTH + IDENTITY

Complete and verify:
- OTP generation, hashing, expiry and attempt/request controls;
- cooldown/rate limits and anti-enumeration;
- identity creation/lookup;
- device registration with distinct device ID and public-key concepts;
- session creation;
- short-lived access tokens;
- refresh rotation/revocation;
- logout/revoke-device;
- account recovery;
- suspicious-login/device signals;
- secure high-risk step-up.

Provider credentials remain server-side. SMS adapters remain replaceable.

## 6. DEVICE + SESSION SECURITY

A revoked device must not leave its sessions usable. Sensitive session operations must verify ownership, expiry, revocation and active-device state. Refresh rotation must be atomic.

## 7. MESSAGING

V1 messaging must progress beyond a REST demo:
- direct conversations;
- groups/membership/roles;
- pagination/cursors;
- realtime delivery;
- delivery/read state;
- offline cache and reconnect sync;
- durable outbound queue where appropriate;
- media and voice notes;
- search;
- block/report;
- push notifications;
- multi-device state;
- safe deletion/edit semantics.

Do not claim E2EE unless the actual implementation provides the promised properties. Never invent cryptography.

## 8. WALLET + MONEY

The server/database is authoritative. Money uses integer minor units.

Required:
- wallet persistence;
- double-entry/ledger records;
- trusted internal credit/debit primitives only;
- authenticated transfers;
- recipient/ownership validation;
- self-transfer prevention;
- strict amount/reference validation;
- idempotency;
- deterministic locking;
- concurrency safety;
- insufficient-funds protection;
- limits and risk checks;
- audit events;
- step-up authorization for sensitive transfers;
- transaction history/pagination;
- reconciliation/dispute foundations.

Never expose arbitrary client-controlled balance mutation.

## 9. PAYMENTS

Keep providers behind an abstraction. Client code never declares settlement success.

Required:
- initialization;
- server-side verification;
- webhook signature verification using raw request evidence;
- amount/currency/reference validation;
- idempotent settlement;
- risk enforcement before wallet credit;
- payment history;
- atomic reversal boundary;
- provider refund/reconciliation only when genuinely implemented;
- adversarial tests;
- audit events.

Never advertise provider refunds if the provider API/webhook path is still unavailable.

## 10. SECURITY CORE

Sensitive flow:

```text
request
→ authentication
→ authorization
→ validation
→ device/security proof
→ risk decision
→ transaction
→ audit
→ response
```

Required: device public keys, challenge/response, active-device checks, atomic challenge consumption, intent binding for sensitive mutations, step-up authorization, security events, security alerts, session/device management, recovery and emergency controls.

Fail closed when a required security dependency is unavailable.

## 11. RISK + ABUSE

Implement deterministic, explainable controls for:
- OTP abuse;
- registration/login/device anomalies;
- transfer/payment velocity;
- repeated failures;
- takeover signals;
- merchant risk;
- spam/abuse;
- rate limits;
- review/block decisions;
- audit trail.

Do not silently create irreversible automated decisions where evidence is weak.

## 12. NOTIFICATIONS + EVENT DELIVERY — NEXT BACKEND PRIORITY

Build a provider-agnostic internal event/delivery system covering:
- security alerts;
- new device/login;
- messages;
- wallet transfers;
- payment status;
- support;
- business/orders.

Required:
- in-app notifications;
- preferences;
- durable event/outbox semantics;
- idempotency;
- delivery status;
- retries/backoff;
- background processing;
- provider failure handling.

Notifications must never contain secrets, OTPs, tokens, signatures or unnecessary financial/security data.

## 13. ADMIN / CONTROL CENTER

Complete least-privilege operations surfaces:
- overview;
- users;
- wallet/payments metadata;
- businesses;
- risk/fraud;
- security;
- support;
- devices/sessions;
- notifications/analytics;
- staff/roles;
- append-only audit;
- emergency controls.

Admins must not casually access private message contents. Emergency controls require strong authorization, explicit confirmation, reason capture and audit.

**Remove WhatsApp from the V1 Control Center.** A future V2 WhatsApp Business connector may add a dedicated area later.

## 14. BUSINESS / MERCHANT

Complete:
- business onboarding/profile;
- owner/staff roles;
- customers;
- products/catalog;
- orders;
- payments;
- merchant wallet/settlement boundaries;
- analytics;
- support/fraud controls.

Consumer wallet permissions and merchant permissions must remain separate.

### Merchant self-ordering rule
A merchant owner/staff account must not create an ordinary customer order against its own business. Reject this server-side unless a future explicitly authorized internal/test flow is designed with separate settlement semantics. Add regression tests.

## 15. OPPA-NATIVE CALLS

Calls are an OPPA feature, not a WhatsApp feature. Use a dedicated architecture for signaling, permissions, media transport, security, call state and network adaptation. Do not invent encryption or expose provider secrets.

## 16. OFFLINE-FIRST

Design for unreliable mobile networks:
- local cache;
- durable outbound queue;
- reconnect sync;
- retries with backoff;
- idempotent mutations;
- compact payloads;
- media optimization;
- data-saving mode;
- clear pending/failed states.

Financial settlement must never depend on optimistic client state.

## 17. FLUTTER APPLICATION

The Flutter application is a real V1 deliverable, not static screens. It must connect to the real API and implement the information architecture above.

Requirements:
- secure credential/key storage;
- real auth/session flow;
- real API integration;
- loading/empty/error/pending states;
- offline/reconnect behavior where applicable;
- accessible controls;
- data-saving behavior;
- theme tokens;
- no provider/payment secrets in the app bundle.

## 18. WEB / TRUST / OPERATIONS

Complete required landing, support, trust/legal and admin surfaces. Maintain the intended Vercel/Render/Supabase/Cloudflare separation. Do not spend development credits on billing or CI/infrastructure work unless a configuration change is strictly required for code correctness.

## 19. QUALITY GATE

A module is complete only when:
1. implementation exists;
2. schema/migrations match runtime;
3. routes are wired;
4. authentication/authorization are correct;
5. validation/failure paths are safe;
6. idempotency/concurrency are addressed where relevant;
7. audit exists where required;
8. success/invalid/unauthorized/adversarial tests exist where relevant;
9. typecheck/build/tests are run and results recorded;
10. no known critical bypass remains;
11. documentation/handoff is updated.

Do not claim verification that was not executed.

## 20. EXECUTION ORDER

```text
1. Verify/close Auth + Identity
2. Verify/close Device + Sessions
3. Complete Messaging
4. Close Wallet
5. Close Payments
6. Final Security Core adversarial audit
7. Complete Risk + Abuse wiring
8. Notifications + Event Delivery
9. Admin / Control Center
10. Business / Merchant
11. OPPA-native Calls
12. Flutter mobile integration
13. Web/Admin/Trust surfaces
14. Operations + Launch QA
15. Browser/VPN/Mini Apps remain deferred
```

WhatsApp is not in this V1 order.

## 21. AUTONOMOUS EXECUTION

Codex should inspect, implement, test, audit, commit coherent batches and continue without waiting for confirmation. Parallelize independent analysis/tests, but never concurrently write the same file.

Before changing a file, inspect its current version. Preserve newer work. Prefer root-cause fixes over cosmetic refactors.

## 22. CREDIT EXHAUSTION

If credits/context/time/environment capacity run out:
- stop starting new work;
- save coherent changes;
- run the fastest meaningful verification;
- commit coherent work;
- update `CODEX_HANDOFF.md`;
- record exact completed/partial/not-done work, files, commit SHAs, verification results, risks and next task.

Never leave the next session guessing where to resume.

## 23. V1 ACCEPTANCE PATH

A user must be able to genuinely traverse:

```text
install
→ onboarding
→ phone verification
→ profile
→ theme
→ home
→ contacts
→ direct/group messaging
→ offline/reconnect behavior
→ notifications
→ wallet
→ secure transfer
→ funding/payment
→ transaction history
→ V1 business/customer path
→ security/devices/recovery
→ support/reporting
```

Operations must have appropriate RBAC, audit and emergency controls.

## 24. FINAL DIRECTIVE

Build OPPA V1 completely and truthfully from the current repository. Do not restart working foundations. Do not fake unavailable integrations. Do not weaken security for speed. Finish and verify each module, then continue to the next.

**WhatsApp is V2 and must not be implemented in V1.**
