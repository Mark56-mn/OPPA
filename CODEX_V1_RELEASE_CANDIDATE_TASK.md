# OPPA — V1 RELEASE CANDIDATE / REAL-DEVICE ACCEPTANCE TASK

## Purpose

This is the additional final task for the OPPA V1 completion sprint.

The goal is to prove that the application is not merely implemented in source code, but works as one connected product across the real backend, database, web/admin surfaces and Flutter Android application.

This task is mandatory after the existing V1 stages and final acceptance audit. Do not mark OPPA V1 complete until this task passes or every blocked item is explicitly documented.

## R — REAL PRODUCT INTEGRATION + RELEASE CANDIDATE ACCEPTANCE

### 1. Re-check the repository first

- inspect latest git history and status;
- read `CODEX_HANDOFF.md`;
- inspect the actual current implementation;
- do not rely on previous completion claims;
- identify any module that was marked complete without functional proof;
- resume unfinished work before beginning release testing.

### 2. Build the complete application

The release candidate must include, where implemented by V1 scope:

- backend API;
- database migrations/schema;
- authentication and sessions;
- messaging;
- notifications;
- wallet/payments/risk/security;
- business/merchant;
- admin/control center;
- OPPA-native calls;
- Flutter Android app;
- required web/trust/support surfaces.

### 3. Real end-to-end journeys

Exercise complete user journeys rather than isolated unit tests.

#### Consumer

```text
install
→ onboarding
→ phone
→ OTP
→ profile
→ device/session
→ home
→ contacts
→ conversation
→ send message
→ receipt/read state
→ notification
→ wallet
→ payment
→ transaction/history
→ security/session management
→ support
```

#### Merchant

```text
business onboarding
→ business profile
→ product
→ staff/roles
→ customer
→ order
→ payment
→ settlement
→ business history
→ support/admin visibility
```

#### Calls

```text
user A
→ invite user B
→ ringing/incoming
→ accept
→ audio/video
→ network degradation
→ reconnect
→ end call
→ call history/state
```

Every flow must use real API/database state. No mocked success responses.

### 4. Offline and poor-network acceptance

Test the application under conditions representing the product's Africa-first requirements:

- no network;
- network loss during message send;
- network restoration;
- repeated reconnects;
- slow network;
- duplicate retry;
- app restart while an operation is pending;
- low-data mode;
- media transfer where applicable;
- financial request interrupted before confirmation.

Verify:

- messages remain visible locally as pending when appropriate;
- retry does not duplicate messages;
- synchronization converges to server truth;
- financial operations never show false success;
- pending/unknown financial states are explicit;
- retries are idempotent;
- the app does not hammer the server during reconnect;
- battery/memory-heavy background loops are avoided.

### 5. Real-device Android acceptance

If an Android build is available, install the release candidate on a real Android device and exercise the core journeys.

At minimum verify:

- launch/startup;
- onboarding;
- OTP/auth flow;
- secure session persistence;
- messaging;
- notifications;
- wallet/payment UI states;
- business flow;
- call permissions and lifecycle;
- offline/reconnect states;
- logout/revocation;
- app restart recovery.

If a real device/build environment is unavailable, mark the mobile integration check `BLOCKED` rather than claiming PASS.

### 6. Final adversarial attack pass

After integration, attack the complete system again as:

- anonymous attacker;
- ordinary user attacking another user;
- malicious merchant/staff;
- lower-privileged admin;
- revoked device/session;
- replaying client;
- concurrent attacker;
- malformed/spam client.

Focus on cross-module attacks:

- auth → wallet;
- auth → payments;
- device/session → security proof;
- messaging → notifications;
- business → wallet settlement;
- admin → emergency controls;
- payment webhook → wallet;
- offline queue → financial mutation;
- calls → authorization/rate limits.

Any discovered vulnerability must be fixed and the attack rerun.

### 7. Release security checks

Confirm that:

- no secrets are committed;
- no provider secret is bundled in Flutter;
- no debug/test backdoors remain;
- no fake/mock production endpoints remain;
- no unsafe admin bypass exists;
- no client-controlled balance/role/identity decision is trusted;
- no sensitive logs expose tokens, signatures or private content;
- no accidental WhatsApp V1 functionality has been introduced;
- V1 scope has not expanded into Browser/VPN/Mini Apps.

### 8. Verification gate

Run what the environment supports:

- full tests;
- adversarial tests;
- concurrency tests;
- typecheck;
- build;
- lint/static checks;
- migration/schema checks;
- API smoke tests;
- mobile build/install tests;
- end-to-end journeys.

Record unavailable checks explicitly.

### 9. Final completion rule

OPPA V1 may only be reported as complete when:

1. the repository implementation matches the V1 scope;
2. the backend and database are verified;
3. security attacks have been attempted and remediated;
4. real end-to-end journeys work;
5. offline/reconnect behavior is verified where supported;
6. Flutter is genuinely connected to the backend;
7. Android build/device verification passes where the environment permits;
8. no critical/high unresolved security defect remains;
9. all blocked verification items are explicitly documented;
10. `CODEX_HANDOFF.md` contains the exact final state.

Do not equate `build succeeded` with `product works`.

Do not equate `tests passed` with `security proven`.

Do not equate `files exist` with `features complete`.

## CREDIT / ENVIRONMENT STOP

If the environment runs out of credits, time, context or device/build capability, stop cleanly and update `CODEX_HANDOFF.md` with:

- exact completed work;
- exact partial work;
- exact blocked checks;
- files changed;
- commits;
- tests/typecheck/build status;
- database/migration status;
- real-device status;
- security findings;
- next exact task.
