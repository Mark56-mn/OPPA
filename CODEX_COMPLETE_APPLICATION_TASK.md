# OPPA AUTONOMOUS V1 COMPLETION TASK

## Mission

Complete OPPA V1 from the **current repository state**. Work autonomously for long sessions. Do not wait for owner confirmation between normal tasks. Finish one module, audit it, verify it, then immediately continue.

The owner will merge manually. Do not spend credits on CI/billing/infrastructure/deployment unless a change is required for application correctness. Do not fake unavailable integrations.

## Mandatory reading

1. `OPPA_MASTER_BUILD_SPEC.md`
2. `CODEX_AUTOPILOT.md`
3. `CODEX_HANDOFF.md`
4. `CODEX_BUILD_MAP.md`
5. Current git status/tree/history
6. Relevant implementation, migrations and tests

The repository is the source of truth. Existing files are not proof of completion.

## LOCKED V1 PRODUCT SCOPE

V1 is OPPA's own platform: identity, security, messaging, wallet, payments, risk, notifications, business, OPPA-native calls, Flutter application and required web/admin/trust/operations surfaces.

### WhatsApp is NOT V1

Do not implement or expose any WhatsApp capability in V1. Specifically do not add:
- WhatsApp API/Cloud API integration;
- WhatsApp OAuth/account linking;
- WhatsApp Business onboarding;
- WhatsApp inbox or message synchronization;
- WhatsApp-specific routes/database models/UI;
- WhatsApp Web automation/scraping;
- personal WhatsApp message/contact import;
- WhatsApp calls.

Remove or isolate stale WhatsApp V1 references so they cannot become runtime dependencies. Do not create a fake placeholder that suggests WhatsApp is connected.

WhatsApp is a **V2 optional OPPA Business external-channel strategy**. It may later allow eligible businesses to use OPPA as their operating layer while optionally communicating through officially authorized WhatsApp Business capabilities. V2 begins only after fresh verification of Meta documentation, eligibility, permissions, policies, pricing and App Review requirements.

OPPA must never present itself as WhatsApp or as affiliated with WhatsApp.

## V1 EXECUTION ORDER

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
13. Web/Admin/Trust surfaces
14. Operations + Launch QA
```

Do not skip ahead merely because a later module is easier. Change order only when a real dependency requires it, and document why.

## BUSINESS SAFETY BLOCKER

Before declaring Business complete, fix the identified merchant self-ordering issue:

- merchant owner/staff must not create an ordinary customer order against their own business;
- enforce server-side;
- ensure no ordinary customer settlement/reward/fee path can be manufactured through self-ordering;
- add regression tests;
- do not rely on UI prevention.

## MODULE WORKFLOW

For every module:

### 1. Inspect
- source files;
- interfaces/services/repositories;
- migrations/schema;
- routes/controllers;
- tests;
- server registration;
- configuration;
- end-to-end data flow.

### 2. Implement
- reuse existing abstractions;
- avoid duplicate services;
- keep provider integrations behind adapters;
- keep business/security decisions server-side;
- use integer minor units for money;
- use transactions and deterministic locks for money;
- use established cryptographic protocols only;
- never create fake success paths.

### 3. Security review
Check authentication, authorization/ownership, validation, enumeration, replay, idempotency, concurrency/races, brute force, rate limits, privilege escalation, insecure direct object references, secret leakage, SSRF/path/file risks where applicable, auditability and fail-closed behavior.

### 4. Verification
Run available targeted tests, full tests, typecheck, build, lint/static checks and schema/migration checks. Run adversarial/replay/concurrency tests where relevant.

If Postgres integration tests require `DATABASE_URL` and it is unavailable, do not pretend they passed. Record the exact limitation and continue with work that can be safely verified.

### 5. Diff audit
Search the final changes for TODOs, stubs/501 paths, fake data, hard-coded secrets, hard-coded authorization, dead routes, missing migration wiring, unsafe error leakage, client-controlled financial state and security bypasses.

### 6. Completion
Only mark the module complete when implementation, persistence, route wiring, authorization, failure handling, relevant idempotency/concurrency, tests and build compatibility are addressed.

## CROSS-CUTTING FINANCIAL RULES

Never allow the client to declare payment success, mutate balances, choose ledger state, bypass risk, bypass step-up or alter settled amounts.

Money mutation flow:

```text
request
→ authentication
→ authorization
→ validation
→ security proof/step-up where required
→ risk decision
→ atomic business transaction
→ audit
→ response
```

Never advertise provider refunds until actual provider refund APIs/webhooks are implemented.

## CROSS-CUTTING SECURITY RULES

- revoked devices/sessions must not remain usable;
- sensitive authorization must be bound to the intended operation;
- challenges must be one-time and race-safe;
- secrets never enter source control, Flutter bundles, logs or prompts;
- never invent cryptography;
- fail closed when required security dependencies are unavailable.

## MOBILE TARGET

Flutter V1 must be a real application connected to the API, not static mock screens.

Required journey:

```text
Onboarding → Phone → OTP → Profile → Theme → Home
→ Chats → Contacts → Wallet → Payments → Business
→ Connect → Me/Security
```

Use one tokenized design system:
- Fluid Africa
- OPPA Pulse
- Everyday OPPA

Theme changes visual tokens only. Include loading, empty, error, pending and offline/reconnect states where applicable. Keep credentials/device keys in secure storage and never ship provider/payment secrets.

## NOTIFICATIONS

Build a provider-agnostic event/delivery layer with in-app notifications, preferences, durable event/outbox semantics, idempotency, status, retry/backoff and background processing. Never place OTPs, tokens, signatures or unnecessary sensitive financial/security information into notification payloads.

## ADMIN

Complete least-privilege operations surfaces, RBAC, audit and emergency controls. Admins must not casually read private message contents.

## BUSINESS

Complete business onboarding, profiles, staff roles, customers, products, orders, payments, merchant wallet/settlement boundaries, analytics and fraud/support controls. Keep consumer and merchant permissions separate.

## CALLS

Implement OPPA-native voice/video calls separately from any external platform. Use dedicated signaling/media/security architecture. Do not call this WhatsApp functionality.

## V1 OUT OF SCOPE

Browser expansion, VPN, Mini Apps and WhatsApp integration are deferred. Do not let them consume V1 implementation time.

## SPEED PROTOCOL

Batch independent reads/searches/tests. Work in coherent vertical slices. Do not repeatedly rediscover the repository. Fix root causes. Do not sacrifice security for speed.

## CREDIT EXHAUSTION — MANDATORY

If credits/context/time/environment capacity run out:
1. stop starting new work;
2. save coherent changes;
3. run the fastest meaningful verification;
4. commit coherent work;
5. update `CODEX_HANDOFF.md` immediately;
6. record exact completed/partial/not-done work, files, commit SHAs, verification, risks and next task.

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

Never claim unverified work is complete.

## FINAL COMMAND

Do the work, not merely the description. When one verified module is finished, move to the next unfinished V1 module without waiting for the owner. When V1 acceptance is genuinely satisfied, stop expanding scope and prepare the repository for release/owner review.
