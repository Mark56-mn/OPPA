# OPPA AUTONOMOUS COMPLETION TASK — 2026-09-03

## Mission

Complete the OPPA application from the CURRENT repository state to the V1 definition in `OPPA_MASTER_BUILD_SPEC.md`.

You have authorization to work autonomously for long sessions. Do NOT wait for the owner after each normal task. Work module-by-module, but finish each module before moving onward.

The owner will perform final merges manually. Do NOT spend time on billing, CI/infrastructure setup, cloud deployment, or production credentials unless required to make application code structurally correct. Your job is implementation, code quality, security, tests, and durable handoff.

## Read first — mandatory

1. `README.md`
2. `OPPA_MASTER_BUILD_SPEC.md`
3. `CODEX_AUTOPILOT.md`
4. `CODEX_HANDOFF.md`
5. Current git status/tree/history
6. Actual source/tests/migrations for the active module

The repository is the source of truth. Do not assume a file means a feature is complete.

## Current known state

The backend already has substantial foundations for:

- Auth/OTP/Identity
- Device/Session
- Profile/Contacts
- Messaging
- Wallet/Transfers/Ledger
- Payments/Paystack/Flutterwave foundations
- Security Core
- Risk & Abuse
- Admin/RBAC

Recent Security Core and Risk/Wallet work has been documented as tested in previous sessions. Independently inspect the CURRENT main branch before relying on those claims.

### Important known limitations

- Postgres integration tests may require `DATABASE_URL`.
- Payment provider refund APIs are not complete; never advertise real refunds until provider refund APIs/webhooks are genuinely implemented.
- Risk signals such as registration/login/device/merchant/spam anomaly signals may still need wiring.
- Admin Control Center currently has a risk-management seed and needs completion.
- Notifications/Event Delivery is incomplete.
- Business is incomplete.
- Authorized WhatsApp/Calls are incomplete.
- Flutter mobile UI is incomplete.
- Web/admin/trust surfaces are incomplete.
- Operations/launch QA is incomplete.
- Browser is V1.5/later, VPN V2, Mini Apps post-V1 unless the master spec is changed.

## EXECUTION ORDER

Follow this order unless a dependency makes another order objectively safer:

1. Auth + Identity closure
2. Device + Session closure
3. Messaging completion
4. Wallet completion
5. Payments completion
6. Security Core final adversarial audit
7. Risk & Abuse completion
8. Notifications/Event Delivery
9. Admin/Control Center
10. Business/Merchant
11. Authorized WhatsApp + Calls
12. Flutter mobile application integration
13. Web/Admin/Trust surfaces
14. Operations/Launch QA
15. Browser V1.5 only if explicitly brought into scope
16. VPN V2 only
17. Mini Apps post-V1

Do not move to the next module until the active module passes its own completion gate.

## MODULE COMPLETION GATE

For EVERY module:

### A. Inspect
- Read all relevant implementation files.
- Read repository interfaces and DB repositories.
- Read migrations.
- Read routes/controllers.
- Read tests.
- Trace the request/data flow end-to-end.

### B. Implement
- Reuse existing abstractions.
- Avoid duplicate services.
- Keep providers behind adapters.
- Keep business/security decisions server-side.
- Keep financial state in integer minor units.
- Use transactions and deterministic locking for money.
- Use established cryptographic libraries/protocols.
- Never invent cryptography.
- Never create fake provider success paths.

### C. Security audit
Check:
- authentication
- authorization/ownership
- input validation
- output/error leakage
- replay
- idempotency
- concurrency/races
- enumeration
- brute force
- rate limiting
- secret exposure
- SSRF/file/path injection where applicable
- privilege escalation
- insecure direct object references
- auditability
- fail-closed behavior

### D. Verification
Run what is available:
- targeted tests
- full tests
- typecheck
- build
- lint/static checks
- migration/schema checks
- adversarial tests

If a test cannot run because an external dependency is unavailable, record exactly why. Do not pretend it passed.

### E. Review
Inspect the final diff and search for:
- TODO placeholders
- 501/unimplemented paths
- fake data
- hard-coded secrets
- hard-coded authorization decisions
- dead routes
- inconsistent status/error codes
- missing migrations
- missing route registration
- client-controlled financial settlement
- security bypasses

### F. Mark complete
Only mark a module complete when implementation + wiring + persistence + authorization + failure handling + tests + build compatibility are addressed.

## SPEED PROTOCOL

You are expected to work quickly and continuously.

- Batch independent file reads/searches.
- Batch independent analysis.
- Do not repeatedly rediscover repository structure.
- Do not spend time on cosmetic refactors unrelated to the active module.
- Fix root causes rather than symptoms.
- Prefer complete vertical slices over isolated stubs.
- When one module is verified, immediately start the next.
- Never sacrifice security or correctness merely to increase speed.

## MOBILE PRODUCT TARGET

The Flutter application must ultimately implement the complete mobile experience in the master spec:

Onboarding → phone OTP → profile → theme selection → Home → Chats → Contacts → Wallet → Payments → Business → Connect → Me/Security.

Use one tokenized design system supporting:
- Fluid Africa
- OPPA Pulse
- Everyday OPPA

Do not duplicate application logic per theme.

Mobile requirements include:
- offline-first appropriate data
- durable outbound queue
- sync/reconciliation
- loading/empty/error/pending states
- data-saving behavior
- accessible controls
- secure storage for credentials/keys
- no provider/payment secrets in the client

## FINANCIAL SAFETY

Never allow the client to:
- declare payment success
- credit/debit arbitrary balances
- bypass risk
- bypass step-up authorization
- choose ledger state
- alter settled payment amounts

Money mutations must be:
- authenticated
- authorized
- validated
- idempotent
- transactionally safe
- concurrency-safe
- auditable

## SECURITY SAFETY

Sensitive operation flow must remain:

request
→ authentication
→ authorization
→ validation
→ device/security proof
→ risk decision
→ business transaction
→ audit event
→ response

Revoked devices/sessions must not remain usable.

## INTEGRATION POLICY

Implement real adapters and real application wiring.

If an external provider cannot be configured or exercised in this environment:
- build the correct interface
- implement safe parsing/validation/error handling
- add tests with controlled fixtures where appropriate
- explicitly record what remains externally dependent
- never pretend the integration is live

## DOCUMENTATION / HANDOFF

Update `CODEX_HANDOFF.md` after every major coherent batch and whenever a session is stopping.

At minimum record:

SESSION STOP REASON:
COMPLETED:
FILES CHANGED:
COMMITS:
VERIFIED:
PARTIALLY COMPLETED:
NOT DONE:
KNOWN FAILURES/RISKS:
NEXT EXACT TASK:
MANUAL OWNER ACTION:

If you run out of credits/context/time:
- stop starting new work
- save coherent work
- verify what can be verified
- update the handoff
- leave the exact resume point

Never claim unverified work is complete.

## FINAL V1 DEFINITION

V1 is complete only when a user can genuinely traverse:

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
→ wallet funding/payment
→ transaction history
→ included business path
→ security/devices/recovery
→ support/reporting

Operations must also have the necessary RBAC, audit and emergency controls.

## FINAL COMMAND

Do the work, do not merely describe it.

When the owner says "check the repo, there is a new task file", find this file and execute it together with the master spec, autopilot contract and handoff.

The owner wants implementation speed and will manually merge. Do not block on CI/billing/infrastructure work.

Finish the current module, audit it, verify it, then move to the next unfinished module until credits or the V1 definition is exhausted.
