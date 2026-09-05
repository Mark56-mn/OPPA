# OPPA — ONE-SESSION AUTONOMOUS V1 COMPLETION TASK

## Mission

Complete the remaining OPPA V1 application from the current `main` repository state in **one autonomous Codex session**.

Do not stop after the backend audit. Do not wait for owner confirmation between normal tasks. Finish, audit and verify one module, then immediately continue to the next unfinished V1 module until V1 is genuinely complete or the environment runs out of credits/time/context/capacity.

The repository is the source of truth. Existing documentation and historical claims are not proof of completion. Inspect actual source, migrations, tests, configuration and git history before deciding what is done.

The owner will merge application work manually.

### Do not spend time on
- billing;
- CI/CD unless required for application correctness;
- production infrastructure/deployment work unless required for application correctness;
- unrelated refactors;
- speculative features;
- V2 work.

Do not fake unavailable integrations. Do not mark unverified work complete.

---

# 1. MANDATORY READING

Read these before implementation:

1. `OPPA_MASTER_BUILD_SPEC.md`
2. `CODEX_AUTOPILOT.md`
3. `CODEX_HANDOFF.md`
4. `CODEX_BUILD_MAP.md`
5. `CODEX_BACKEND_ADVERSARIAL_AUDIT_TASK.md`
6. Current git status/tree/history
7. Relevant implementation, migrations and tests

Then inspect the actual repository and establish the real starting point.

---

# 2. LOCKED V1 SCOPE

V1 is OPPA's own platform:

- identity/authentication;
- devices/sessions/security;
- messaging;
- offline/reconnect synchronization;
- notifications/event delivery;
- wallet;
- payments;
- risk/abuse;
- business/merchant;
- admin/control center;
- OPPA-native voice/video calls;
- Flutter mobile application;
- required web/admin/trust/operations surfaces;
- support/reporting;
- launch QA/readiness.

## WhatsApp is NOT V1

Do not implement or expose:

- WhatsApp API/Cloud API integration;
- WhatsApp OAuth/account linking;
- WhatsApp Business onboarding;
- WhatsApp inbox/message synchronization;
- WhatsApp-specific routes/database models/UI;
- WhatsApp Web automation/scraping;
- personal WhatsApp contact/message import;
- WhatsApp calls.

WhatsApp remains a **V2 optional OPPA Business external-channel strategy** only. Never make WhatsApp a V1 runtime dependency and never imply OPPA is WhatsApp or affiliated with WhatsApp.

Also keep Browser expansion, VPN and Mini Apps out of V1 unless the existing master specification explicitly changes scope.

---

# 3. EXECUTE ALL REMAINING STAGES IN THIS ORDER

```text
A. Backend adversarial/security/integration closure
B. Auth + Identity final closure
C. Device + Session final closure
D. Messaging final completion
E. Wallet final closure
F. Payments final closure
G. Security Core final hardening
H. Risk + Abuse completion/wiring
I. Notifications + Event Delivery completion
J. Admin / Control Center completion
K. Business / Merchant completion
L. OPPA-native Calls
M. Flutter mobile application
N. Africa-first offline/network/data resilience
O. Web/Admin/Trust/support surfaces
P. Operations + Launch QA
Q. Final V1 acceptance audit
```

If a dependency requires a small ordering change, make the smallest safe change and document why in `CODEX_HANDOFF.md`.

**Do not stop after A.** The purpose of this task is to continue through every remaining stage in this session.

---

# 4. A — BACKEND ADVERSARIAL SECURITY + INTEGRATION CLOSURE

Start here, using `CODEX_BACKEND_ADVERSARIAL_AUDIT_TASK.md` as the detailed security checklist.

Audit the real implementation, database schema/migrations and every API route.

Attack the application from the perspective of:

- anonymous user;
- ordinary authenticated user;
- second ordinary authenticated user;
- device owner with revoked device/session;
- malicious merchant/staff member;
- lower-privileged admin/staff account;
- replaying attacker;
- concurrent/racing attacker;
- malformed-input attacker;
- spam/abuse attacker.

Specifically test for:

- IDOR/BOLA;
- cross-user data access;
- cross-business/tenant access;
- privilege escalation;
- role confusion;
- device/session bypass;
- token replay;
- OTP brute force/replay/enumeration;
- challenge replay/race;
- payment replay;
- duplicate settlement;
- wallet double-spend/double-credit;
- payment reversal abuse;
- notification authorization;
- message/conversation membership bypass;
- merchant self-ordering;
- enumeration and information leakage;
- unsafe errors;
- secret exposure;
- insecure defaults;
- missing rate limits where required;
- race conditions and transaction isolation problems;
- database privilege bypass;
- migration/schema drift;
- provider/webhook authenticity and replay.

Fix every real in-scope defect. Add regression/adversarial/concurrency tests.

If `DATABASE_URL` is available, run real migration/integration checks. If unavailable, explicitly record integration as BLOCKED; never pretend it passed.

---

# 5. AUTH / IDENTITY / DEVICE / SESSION

Complete the end-to-end lifecycle:

```text
phone → OTP → identity → device → session → access token
→ refresh → revoke → logout → recovery
```

Verify:

- OTP lifetime/attempt/request limits;
- replay protection;
- suspicious-login/risk integration;
- device binding;
- device revocation;
- session revocation;
- refresh-token rotation/replay handling;
- account recovery;
- safe account enumeration behavior;
- security event recording;
- secure storage expectations for mobile.

No client-controlled identity, role or security decision may be trusted.

---

# 6. MESSAGING

Complete a real messaging vertical slice, not mock UI.

Required capabilities as applicable to the existing product specification:

- direct conversations;
- groups;
- membership authorization;
- send/history/pagination;
- unread counts;
- edit/delete where specified;
- delivery/read receipts;
- notifications;
- multi-device synchronization;
- realtime/reconnect behavior;
- message idempotency;
- media architecture/integration where required;
- safe authorization on every conversation/message operation.

Never allow a user to read/write another user's private conversation merely by changing an ID.

---

# 7. AFRICA-FIRST OFFLINE / NETWORK REQUIREMENT

This is a core V1 requirement, not polish.

OPPA is being built for African users where connectivity may be slow, intermittent, expensive or unavailable for periods of time, and where many users may have lower-end Android devices.

Implement and verify:

### Client/network
- local cached state for core screens;
- durable outbound queue for appropriate mutations;
- automatic reconnect;
- exponential backoff with jitter;
- request timeouts;
- retry classification;
- idempotency keys/references for retryable mutations;
- pagination instead of huge responses;
- compact payloads;
- avoid wasteful polling;
- explicit loading/pending/failed/offline states;
- data-saving mode;
- storage/cache controls;
- graceful behavior on app restart while work is pending.

### Messaging

A message must not disappear simply because the network failed.

```text
compose
→ local pending
→ attempt send
→ retry/reconnect
→ server acknowledgement
→ synchronized state
```

### Financial operations

Never display financial success merely because a client request was queued or retried.

```text
offline/uncertain
→ pending/unknown
→ server authorization
→ atomic server transaction
→ confirmed result
```

The server/database remains authoritative for balances, payment state and settlement.

### Media

Where media is implemented:

- compression;
- thumbnails/previews;
- resumable/retryable transfer where appropriate;
- no automatic large downloads by default;
- data-saving controls.

### Low-end Android

Avoid unnecessarily heavy dependencies, excessive memory use, huge initial payloads and battery-expensive background work.

---

# 8. WALLET + PAYMENTS

Complete the secure financial path:

```text
request
→ auth
→ authorization
→ validation
→ device/security proof where required
→ risk
→ atomic transaction
→ ledger
→ audit
→ response
```

Rules:

- integer minor units only;
- server/database authoritative;
- deterministic locking;
- atomic mutations;
- idempotency;
- no client balance mutation;
- no client-declared payment success;
- no bypass of risk or step-up;
- no duplicate settlement;
- safe retries;
- correct history;
- reconciliation boundaries;
- webhook authenticity and replay protection.

For Paystack/Flutterwave:

- verify actual provider responses;
- verify amount/currency/reference ownership;
- persist provider state safely;
- make settlement idempotent;
- implement actual provider refund/reversal paths only where provider APIs/webhooks are truly available;
- never fake a refund.

---

# 9. SECURITY / RISK / ABUSE

Complete the Security Core and risk wiring.

Verify:

- one-time/race-safe challenges;
- intent-bound sensitive authorization;
- device-bound proof;
- fail-closed security dependencies;
- replay resistance;
- rate limits;
- suspicious login/device/payment signals;
- merchant abuse/spam signals;
- operational risk visibility;
- security event/audit trails.

Never invent cryptography.

---

# 10. NOTIFICATIONS + EVENT DELIVERY

Complete the durable event system:

- event model;
- in-app notifications;
- preferences;
- durable outbox;
- idempotency;
- retries/backoff;
- processing status;
- failure tracking;
- background processing;
- safe payloads.

Never place OTPs, access/refresh tokens, private signatures or unnecessary sensitive financial/security information into notification payloads.

---

# 11. ADMIN / CONTROL CENTER

Complete least-privilege operational capabilities:

- staff/RBAC;
- user/account operations;
- device/session/security visibility;
- payment/risk operations;
- business operations;
- audit events;
- emergency controls;
- support workflows;
- operational status.

Admins must not casually read private message contents. Use minimum necessary access.

---

# 12. BUSINESS / MERCHANT

Complete the business vertical slice:

- business onboarding;
- business profile;
- staff;
- roles/permissions;
- customers;
- products;
- orders;
- payments;
- settlement boundaries;
- analytics appropriate to V1;
- fraud/support controls.

### Mandatory self-order blocker

A business owner/staff account must not create an ordinary customer order against its own business.

Enforce this server-side and test it. Do not rely on UI.

Keep consumer and merchant permissions separate.

---

# 13. OPPA-NATIVE CALLS

After backend/security gates pass, implement OPPA-native calls.

Do not use or imply WhatsApp functionality.

Implement the required architecture for:

- call invitation/signaling;
- incoming/outgoing states;
- permission handling;
- voice;
- video;
- call lifecycle/history;
- reconnect/failure handling;
- security;
- abuse/rate controls;
- adaptive network behavior.

### Africa-first call behavior

Design for unstable networks:

- adaptive quality;
- bandwidth-aware degradation;
- audio-first fallback;
- reconnection;
- clear connection state;
- avoid repeated expensive reconnect loops;
- graceful call termination.

Do not invent a proprietary media cryptosystem. Use established protocols/libraries and document security assumptions.

---

# 14. FLUTTER MOBILE APPLICATION

If Flutter is absent/incomplete, create/complete the real V1 application in the repository.

The mobile app must be connected to the real API. Do not build static mock screens.

Required journey:

```text
Install
→ Onboarding
→ Phone
→ OTP
→ Profile
→ Theme
→ Home
→ Chats
→ Contacts
→ Wallet
→ Payments
→ Business
→ Calls
→ Connect
→ Me/Security
→ Support
```

Implement real API integration, state management, authentication/session lifecycle, error states and offline/reconnect behavior.

### Design system

Use the existing OPPA design direction and three themes:

- Fluid Africa
- OPPA Pulse
- Everyday OPPA

Theme changes visual tokens, not functionality.

Build reusable tokens/components rather than one-off screen code.

Include:

- loading;
- empty;
- error;
- pending;
- offline;
- reconnecting;
- success/failure states;
- accessible touch targets;
- appropriate typography/layout for small Android screens;
- data-saving controls;
- secure credential/device-key storage.

Never put provider/payment secrets in the Flutter app.

### Exact UI responsibility

Codex may build and wire the Flutter UI when the repository contains sufficient design/source information. Reuse the existing OPPA themes/specifications and make the implementation coherent and production-ready.

However, do **not** invent a claim that a screen exactly matches an owner-approved visual design when no such design artifact exists in the repository. If the owner later supplies exact Figma/screenshots/design tokens, the UI can be refined against those artifacts without changing backend contracts.

The primary objective in this session is to deliver the complete functional mobile application and its API/offline wiring, not to spend the whole session on cosmetic perfection.

---

# 15. WEB / ADMIN / TRUST / SUPPORT

Complete the required V1 launch surfaces only.

At minimum, cover the product's required:

- public/product information;
- support/contact/reporting;
- trust/security information;
- legal/privacy surfaces;
- admin/control-center interface where required;
- safe authenticated/admin routing.

Do not build V1 Browser expansion or unrelated web products.

---

# 16. OPERATIONS + LAUNCH QA

Perform a final production-readiness pass over the application.

Verify:

- environment configuration;
- secrets are not committed or bundled;
- health/readiness behavior;
- database migrations;
- indexes/constraints;
- RLS/privileges/access model;
- logs do not leak secrets/tokens/private content;
- error responses are safe;
- rate limits exist where required;
- background workers do not create duplicate effects;
- payment/webhook retries are safe;
- backups/recovery assumptions are documented;
- monitoring/operational failure modes are documented where implementation exists.

Do not spend the session building elaborate infrastructure if application correctness does not require it.

---

# 17. DATABASE HARDENING

Audit the real database, not only migration files.

Check:

- all required migrations applied;
- primary keys;
- foreign keys;
- unique constraints;
- check constraints;
- tenant/business boundaries;
- transaction semantics;
- indexes for critical paths;
- public schema privileges;
- default privileges for future objects;
- RLS/access model;
- exposed Data API surface;
- views/functions and security context.

Pay particular attention to business order/product relationships and ensure an order cannot reference a product from another business through a missing cross-tenant integrity boundary.

Do not blindly add RLS policies that conflict with the backend's actual privileged-access architecture. First establish the access model, then harden it.

---

# 18. VERIFICATION AFTER EVERY MODULE

For each module:

1. inspect source/interfaces/routes/migrations/tests;
2. implement the complete vertical slice;
3. run targeted tests;
4. run relevant adversarial/replay/concurrency tests;
5. run full tests where practical;
6. run typecheck;
7. run build;
8. run lint/static checks available in the repository;
9. run schema/migration checks;
10. inspect the final diff;
11. search for TODOs, stubs, fake data, hard-coded secrets, unsafe authorization and dead routes;
12. update `CODEX_HANDOFF.md` with the real state.

If a test cannot run, state exactly why.

---

# 19. NO FAKE COMPLETION

Never claim any of the following unless verified:

- migration applied;
- payment provider integration works;
- refund works;
- webhook works;
- call works;
- offline sync works;
- mobile build works;
- admin authorization works;
- database security is correct.

A compile/build success is not functional proof.

A passing unit test is not integration proof.

A file existing is not feature proof.

---

# 20. CREDIT / SESSION EXHAUSTION

If the session runs out of credits, context, time or environment capacity:

1. stop starting new work;
2. save coherent changes;
3. run the fastest meaningful verification possible;
4. commit coherent work;
5. update `CODEX_HANDOFF.md` immediately;
6. record exact completed/partial/not-done work;
7. list files changed;
8. list commits;
9. record tests/typecheck/build/migration/integration status;
10. record known failures/risks;
11. give the next exact task.

Use this exact format:

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
- lint/static: PASS/FAIL/NOT RUN
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
```

Never leave the next session guessing where to resume.

---

# 21. FINAL V1 ACCEPTANCE GATE

Do not declare V1 complete until the repository can support a genuine end-to-end path:

```text
Install
→ onboarding
→ phone verification
→ profile/theme
→ authenticated session
→ contacts
→ messaging
→ offline/reconnect
→ notifications
→ wallet
→ secure transfer
→ funding/payment
→ payment history
→ business/customer functionality
→ security/devices/recovery
→ OPPA-native calls
→ support/reporting
→ admin/RBAC/audit/emergency controls
→ required web/trust surfaces
```

And the implementation has passed the applicable security, correctness, persistence, integration and build gates.

If something remains genuinely unfinished, do not hide it. Record it precisely in `CODEX_HANDOFF.md`.

---

# 22. FINAL COMMAND

**Execute the work now.**

Start from the actual current repository state. Complete the backend adversarial audit first. Then continue automatically through every remaining V1 stage listed above in this same session.

Do not ask the owner whether to continue.

Do not stop because one stage is finished.

Do not switch to WhatsApp, Browser expansion, VPN, Mini Apps, billing or unrelated infrastructure.

Do not sacrifice security for speed.

Do not spend time rewriting documentation instead of implementing the application.

When one verified module is complete, immediately move to the next unfinished module.

When capacity is exhausted, execute the mandatory handoff protocol.

When V1 acceptance is genuinely satisfied, stop expanding scope and prepare the repository for owner review.
