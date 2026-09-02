# Codex Handoff

## Purpose
Durable handoff for autonomous Codex sessions. Update this file whenever a session ends because of credits, context, time, environment limits or interruption.

## Last initialized
2026-09-02

## Read first
1. `OPPA_MASTER_BUILD_SPEC.md` — complete application/product/build map.
2. `CODEX_AUTOPILOT.md` — autonomous operating contract.
3. `CODEX_BUILD_MAP.md` — current implementation map and execution plan.
4. This file — current durable session state.

## Current repository reality
The OPPA repository contains a substantial TypeScript backend foundation under `apps/api/src`, including Auth/OTP/Identity/Device/Session/SMS, Profile, Contact, Messaging, Wallet, Payments, Admin and Security modules, plus migrations, CI and Codex documentation.

A detailed current-state/target-state map is maintained in `CODEX_BUILD_MAP.md`. Do not rebuild the foundation blindly. Inspect the actual current branch, code, migrations and tests before changing anything.

## Product target
Build the complete OPPA application described by `OPPA_MASTER_BUILD_SPEC.md`: phone-first identity/authentication; secure messaging; groups/media/realtime/offline sync; wallet and transfers; payment integrations/settlement/refunds/reconciliation; Security Core/recovery; Risk & Abuse; notifications/events; Admin/Control Center; Business/merchant capabilities; authorized WhatsApp-connected capabilities and calls; Flutter mobile; web/admin/trust surfaces; and production operations/launch readiness.

The three tokenized themes apply across the product:
- Fluid Africa
- OPPA Pulse
- Everyday OPPA

Browser is V1.5/later, VPN is V2, and Mini Apps are post-V1 unless the master specification is deliberately changed.

## Execution rule
Continue autonomously through coherent implementation batches. Do not stop for confirmation between normal tasks. Inspect first, implement, test, fix, audit, commit, and continue.

Preferred order:
1. Auth/Identity closure
2. Messaging completion
3. Wallet closure
4. Payments closure
5. Security Core closure
6. Risk & Abuse
7. Notifications/Event Delivery
8. Admin/Control Center
9. Business
10. Authorized WhatsApp/Calls
11. Flutter + web/admin integration
12. Operations/Launch QA
13. Browser V1.5
14. VPN V2
15. Mini Apps post-V1

If dependencies force another order, document the reason here before proceeding.

## Verification rule
Historical test results are not current proof. Re-run tests, typecheck, build, lint and relevant database/integration checks against the current repository before declaring anything complete.

A module is complete only when implementation, wiring, persistence, authorization, safe failure paths, relevant idempotency/concurrency, auditability, tests and deployment compatibility are verified.

## Credit exhaustion protocol — mandatory

If Codex runs out of credits/context/time/environment capacity:

1. Stop starting new work.
2. Save all coherent completed changes.
3. Run the fastest meaningful checks available.
4. Commit coherent work.
5. Update this file immediately.
6. Clearly separate completed, partially completed and not-done work.
7. Leave the exact next task and any manual owner action.
8. Never claim unverified completion.

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

## Security reminder
Never expose secrets. Never put provider credentials in Flutter, GitHub, logs or prompts. Never invent cryptography. Never bypass platform/provider controls. Never let the client decide financial settlement, balances, roles or security authorization. Fail closed when required security dependencies are unavailable.

## Current session status
This handoff was refreshed alongside `CODEX_BUILD_MAP.md` on 2026-09-02. The next Codex session must read the master spec, autopilot contract and build map, inspect current git/source state, rerun verification, then continue from the highest-priority unfinished module.
