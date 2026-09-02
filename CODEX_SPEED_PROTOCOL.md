# OPPA Codex Speed Protocol — Read Before Starting

This is an addendum to CODEX_AUTOPILOT.md. It exists to maximize autonomous work while preserving the security gate.

## SPEED MODE

Do not wait for user confirmation between tasks. Work continuously until credits/time stop you.

### Priority order NOW

1. Audit current main branch and current Security Core implementation.
2. Finish the remaining Security Core gaps:
   - cryptographically bind sensitive authorization to the exact operation/transaction intent, including wallet transfer recipient, amount, currency and idempotency/reference where appropriate;
   - ensure failed device proofs increment attempts and create security events;
   - enforce challenge expiry, one-time consumption and replay protection atomically;
   - add PostgreSQL integration tests for concurrent challenge consumption;
   - verify wallet transfer and payment reversal authorization end-to-end.
3. Run typecheck, build and all available tests. Fix failures immediately.
4. Update CODEX_HANDOFF.md with only verified results.
5. Commit coherent batches.
6. Once Security Core meets Definition of Done, immediately start Risk & Abuse.
7. Continue into Notifications & Event Delivery without waiting for the owner.
8. Continue down the roadmap as long as credits/time remain.

## PARALLEL EXECUTION

Run independent workstreams in parallel when safe, for example:
- tests + repository inspection
- migrations + isolated service implementation
- independent module tests
- documentation/handoff preparation

Never run concurrent writes against the same file. Never overwrite a newer commit blindly.

## SECURITY GATE

Do not mark a module complete because code exists. It is complete only after:
- API wiring is verified
- authorization is enforced server-side
- persistence is correct
- replay/idempotency/concurrency risks are addressed
- negative/security tests exist
- typecheck/build/tests actually execute successfully
- no known critical bypass remains

## FINANCIAL TRANSACTION SIGNING

For wallet/payment sensitive actions, do not accept a generic valid device proof as authorization for arbitrary transaction parameters. The authorization context must be bound to the exact intended operation. Use canonical serialization and domain separation; never invent unsafe cryptography.

## WHEN CREDITS RUN OUT

Before stopping:
- commit completed work
- update CODEX_HANDOFF.md
- list exact commits/files
- report tests actually executed and their results
- list unresolved issues
- identify the single highest-priority next task

Do not leave half-written files or claim unexecuted checks passed.

## AUDIT HANDOFF

The next agent will independently audit your work. Optimize for correctness, clean commits and verifiable evidence—not for appearing complete.
