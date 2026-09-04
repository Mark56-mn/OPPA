# OPPA CODEX AUTOPILOT — V1 OPERATING CONTRACT

## Mission
Build the complete OPPA V1 application from the current repository state. OPPA is a mobile-first African communications + identity + wallet + payments + business + security platform. It is not WhatsApp and is not affiliated with WhatsApp.

## Source of truth
Read, in order:
1. `OPPA_MASTER_BUILD_SPEC.md`
2. `CODEX_AUTOPILOT.md`
3. `CODEX_HANDOFF.md`
4. `CODEX_BUILD_MAP.md`
5. relevant source, migrations and tests

The repository is authoritative. Do not trust historical claims without inspection and executable evidence.

## LOCKED V1 SCOPE

V1 includes OPPA-native identity, security, messaging, wallet, payments, risk, notifications, business, OPPA-native calls, Flutter mobile and required web/admin/trust/operations surfaces.

**WhatsApp is V2 and is completely excluded from V1.** Do not implement WhatsApp API/Cloud API, WhatsApp Business onboarding, account linking, inbox/sync, WhatsApp-specific routes/models/UI, WhatsApp Web automation/scraping, personal WhatsApp contact/message import or WhatsApp calls.

Future V2 may evaluate an optional OPPA Business external-channel integration only after fresh verification of Meta documentation, eligibility, permissions, policies, pricing and App Review requirements. Never build an unofficial connector.

## Non-negotiable engineering rules
1. Security before convenience.
2. Server is authoritative for identity, permissions, balances, payments and sensitive state.
3. Never trust client payment success, balances, roles or security decisions.
4. Sensitive operations require authentication, authorization, validation, idempotency and auditability.
5. Financial mutations are atomic and concurrency-safe.
6. Secrets never enter source control, mobile bundles, logs or prompts.
7. Use parameterized SQL.
8. Fail closed when required security dependencies are unavailable.
9. Never invent cryptography.
10. Preserve replaceable provider interfaces for SMS, payments, storage and future external channels.
11. Avoid unnecessary dependencies.
12. Test happy paths, invalid input, authorization failures and relevant replay/concurrency/abuse cases.
13. Never claim an unexecuted test/build/integration passed.
14. Inspect a file before modifying it and preserve newer work.
15. Never weaken security to make a test pass.
16. Never fake unavailable external integrations.
17. A file existing does not mean a module is complete.
18. Preserve one tokenized UI system for Fluid Africa, OPPA Pulse and Everyday OPPA.
19. Do not allow V2/V1.5 scope to consume V1 implementation time.

## V1 execution order

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

Browser expansion, VPN, Mini Apps and WhatsApp are deferred.

## Autonomous workflow

1. Inspect git status, branch, recent commits and tree.
2. Read the four Codex/product documents above.
3. Read the handoff and identify the highest-priority unfinished V1 module.
4. Inspect the real implementation/migrations/tests.
5. Implement a coherent vertical slice.
6. Batch independent analysis/tests safely; never concurrently write the same file.
7. Run targeted tests, full tests, typecheck, build and other available checks.
8. Fix failures before unrelated expansion.
9. Perform a security/data-flow/diff audit.
10. Commit coherent work and update the handoff.
11. Continue to the next unfinished V1 module without waiting for confirmation.

## Business safety blocker

A merchant owner/staff account must not create an ordinary customer order against its own business. Enforce server-side and test it before Business is complete.

## Financial safety

Never allow the client to declare payment success, mutate balances, choose ledger state, bypass risk/step-up or alter settled amounts. Use integer minor units. Use atomic transactions, deterministic locking, idempotency and audit events.

## Security safety

Sensitive flow:

```text
request → authentication → authorization → validation
→ device/security proof → risk decision → transaction → audit → response
```

Revoked devices/sessions must not remain usable. Never invent cryptography.

## Module completion gate

A module is done only when implementation, persistence/schema, route wiring, authorization, validation, failure handling, relevant idempotency/concurrency, auditability, tests, typecheck/build compatibility and documentation are addressed, with no known critical bypass.

## Credit exhaustion

If credits/context/time/environment capacity run out:
1. stop starting new work;
2. save coherent changes;
3. run the fastest meaningful verification;
4. commit coherent work;
5. update `CODEX_HANDOFF.md` immediately;
6. record completed, files, commits, exact verification, partial/not-done work, risks and next exact task.

Never leave the next session guessing.

## Final V1 gate

V1 is complete only when a real user can traverse install → onboarding → phone verification → profile → theme → home → contacts → direct/group messaging → offline/reconnect → notifications → wallet → secure transfer → funding/payment → transaction history → V1 business/customer path → security/devices/recovery → support/reporting, with required RBAC, audit and emergency controls.
