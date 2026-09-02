# Codex Handoff

## Purpose
Durable handoff for autonomous Codex sessions. Update this file whenever a session ends because of credits, context, time, environment limits or interruption.

## Last initialized
2026-09-02

## Read first
1. `OPPA_MASTER_BUILD_SPEC.md` — complete application/product/build map.
2. `CODEX_AUTOPILOT.md` — autonomous operating contract.
3. This file — current durable session state.

## Current repository reality
The OPPA repository already contains a substantial TypeScript backend foundation under `apps/api/src`, including Auth/OTP/Identity/Device/Session/SMS, Profile, Contact, Messaging, Wallet, Payments, Admin and Security modules. Database migrations and Codex documentation are also present.

Do not rebuild the foundation blindly. Inspect the actual current branch, code, migrations and tests before changing anything.

## Current verified history carried forward
The previous Security Core audit recorded:
- API test suite restored to the repository's Node test runner.
- Device-proof verification validates the presented challenge hash before device signature verification.
- Persisted challenges are atomically consumed.
- Invalid signatures/unavailable active keys record/increment failures.
- Security validation failures map to intentional HTTP statuses.
- Server startup TypeScript issue fixed.
- `PostgresSecurityRepository` restored to active-device validation conformance.

Historical checks recorded as passed:
- `npm test --workspace @oppa/api` — 22 tests.
- `npm run api:typecheck` — passed.
- `npm run build` — passed.
- `git diff --check` — passed.

**These are historical results. The next Codex session must rerun checks against the current repository before relying on them.**

## Product/build target
Build the complete OPPA application described in `OPPA_MASTER_BUILD_SPEC.md`:

- phone-first identity/authentication;
- complete secure messaging;
- groups/media/realtime/offline sync/notifications;
- wallet and secure transfers;
- payment integrations, settlement, refunds/reconciliation;
- Security Core and recovery;
- Risk & Abuse;
- notifications/event delivery;
- Admin/Control Center;
- Business/merchant capabilities;
- authorized WhatsApp-connected capabilities and calls;
- Flutter mobile application;
- web/admin/trust surfaces;
- operations/launch readiness.

Three tokenized themes are required across the application:
- Fluid Africa
- OPPA Pulse
- Everyday OPPA

Browser is V1.5/later unless scope changes. VPN is V2. Mini Apps are post-V1.

## Next execution order
1. Inspect current Security Core state and git history.
2. Rerun build/typecheck/tests.
3. Add/finish route-level integration tests with real PostgreSQL where available.
4. Complete Security Core adversarial audit.
5. Complete Risk & Abuse.
6. Complete Notifications/Event Delivery.
7. Finish Admin/Control Center.
8. Finish Business.
9. Finish authorized WhatsApp/Calls.
10. Build/integrate Flutter mobile and web/admin surfaces against the real API.
11. Complete Operations/Launch QA.
12. Defer Browser/VPN/Mini Apps according to the master spec.

If a dependency requires a different order, record the reason and choose the safest executable path.

## Credit exhaustion protocol — mandatory

If Codex runs out of credits/context/time/environment capacity:

- do not start new work;
- save all coherent completed changes;
- run the fastest meaningful checks available;
- commit coherent work;
- update this file immediately;
- explicitly state completed vs partial vs not done work.

Use this exact structure:

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

Never claim completion for unverified work. Never leave the next session guessing where to resume.

## Security reminder
Never expose secrets. Never put provider credentials in Flutter or GitHub. Never invent cryptography or bypass platform/provider controls. Never let the client decide financial settlement or security authorization.
