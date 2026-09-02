# OPPA Codex Autopilot — Master Build Contract

## Mission
Build the complete OPPA application from the repository's current state, not a demo or isolated backend. OPPA is a mobile-first African communications + identity + wallet + payments + business + security platform with web/operations surfaces and future connectivity capabilities.

## Primary source of truth
**Read `OPPA_MASTER_BUILD_SPEC.md` first.** It is the durable product and engineering map: current repository state, target application, module roadmap, architecture, UX structure, security boundaries, V1/V1.5/V2 scope, quality gates and credit-exhaustion protocol.

Then read:
- `CODEX_AUTOPILOT.md` — operating contract
- `CODEX_HANDOFF.md` — current session state
- relevant implementation, migrations and tests

The repository itself is authoritative for what is actually implemented. Do not trust old claims without inspection and execution evidence.

## Operating rule
Do NOT stop after every tiny task. Inspect, implement coherent batches, test them, fix failures, and continue to the next unfinished item. Optimize for speed without sacrificing correctness or security.

## Current starting point
The backend already has foundations for Auth/OTP/Identity/Device/Session/SMS, Profile/Contact/Messaging, Wallet, Payments, Admin/RBAC and Security Core. The master build spec maps the remaining work. Do not rebuild these systems from scratch; verify and extend them.

## Non-negotiable engineering rules
1. Security before convenience.
2. Server is authoritative for identity, permissions, balances, payments and sensitive state.
3. Never trust client-side payment success, balances, roles or security decisions.
4. Sensitive operations require authentication, authorization, validation, idempotency and auditability.
5. Financial mutations must be atomic and concurrency-safe.
6. Secrets never enter source control, mobile bundles, logs or tests.
7. Use parameterized SQL.
8. Fail closed when required security dependencies are unavailable.
9. Never invent cryptography; use reviewed protocols/primitives and explicit key boundaries.
10. Preserve replaceable provider interfaces for SMS, payments, storage and external messaging.
11. Avoid unnecessary dependencies.
12. Tests must cover happy paths, invalid input, authorization failures and relevant replay/concurrency/abuse cases.
13. Never claim a test/build/deployment/integration passed unless it was actually executed or directly verified.
14. Inspect the current file before modifying it; do not overwrite newer work blindly.
15. Never weaken an existing security control to make a test pass.
16. Do not fake unavailable external integrations; use explicit adapters/configuration and record limitations.
17. Do not mark a module complete merely because files exist.
18. Preserve the three OPPA themes through tokenized UI architecture; never duplicate business logic per theme.

## Architecture

```text
Flutter Mobile ─┐
                ├─ Cloudflare edge/DNS/WAF
Web/Vercel ─────┘
                     ↓
                Render API/worker
                     ↓
                Supabase PostgreSQL
                     ↓
          Storage + SMS + Payments
```

RunCode.io is a development/build environment, not automatically production infrastructure.

## Master execution order

1. Auth/Identity closure
2. Messaging completion
3. Wallet closure
4. Payments closure
5. Security Core closure
6. Risk & Abuse
7. Notifications/Event Delivery
8. Admin/Control Center
9. Business
10. WhatsApp/Calls (only authorized integrations)
11. Flutter mobile + web/admin integration
12. Operations/Launch QA
13. Browser (V1.5)
14. VPN (V2)
15. Mini Apps (post-V1)

Adjust order only when dependency analysis shows a safer path; record the reason in the handoff.

## Autonomous workflow

1. Inspect git status, branch, recent commits and repository tree.
2. Read `OPPA_MASTER_BUILD_SPEC.md`, this file and `CODEX_HANDOFF.md`.
3. Identify the highest-priority unfinished module.
4. Inspect actual code/migrations/tests for that module.
5. Make an implementation checklist.
6. Execute independent work in parallel where safe, but never write the same file concurrently.
7. Run tests/typecheck/build/lint/schema checks after coherent batches.
8. Fix failures before unrelated expansion.
9. Perform a security/data-flow/diff audit.
10. Commit coherent work.
11. Continue to the next unfinished item without waiting for confirmation.

## Credit/session exhaustion — mandatory

If credits, context, execution time or environment limits run out:

1. Stop starting new work.
2. Save all coherent completed changes.
3. Run the fastest meaningful verification available.
4. Commit completed work when the tree is coherent.
5. Update `CODEX_HANDOFF.md` immediately.
6. State exactly:
   - completed work;
   - files changed;
   - commit SHA(s);
   - tests/typecheck/build actually run + results;
   - partially completed work;
   - work not done;
   - known failures/security concerns;
   - exact next task;
   - manual owner actions.
7. Never label unverified work complete.

Required stop format:

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

## Definition of done

A module is done only when implementation exists, API boundaries are wired, persistence is correct, authorization is enforced, failure paths are safe, idempotency/concurrency is addressed where relevant, adversarial tests exist where relevant, executable checks pass, deployment configuration is compatible, no critical bypass is known, and the handoff/audit is updated.

## Final V1 gate

Use `OPPA_MASTER_BUILD_SPEC.md` section 24 as the V1 acceptance definition. V1.5/V2 features must remain explicitly deferred rather than being faked.
