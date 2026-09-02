# Codex Handoff

## Purpose
This file is the durable handoff for autonomous Codex sessions. Update it whenever a session ends because of credits, time, environment limits, or another interruption.

## Last initialized
2026-09-02

## Current focus
Security Core verification/integration, then Risk & Abuse, then Notifications/Event Delivery.

## Completed before this handoff
- Authentication/session foundation
- Device registration/session controls
- Profile/contact/messaging foundations
- Wallet ledger and transfer foundation
- Payment provider/service foundation
- Security Core step-up challenges
- Active-device validation
- Device-bound signature verification
- Sensitive-operation authorization
- Wallet transfer security authorization
- Payment reversal security authorization
- Security-focused tests

## Latest durable build contract
See CODEX_AUTOPILOT.md.

## Audit requirement
The next agent must inspect the actual repository state and git history, verify all claims, run available checks, and fix incomplete or insecure wiring before starting unrelated work.

## Do not assume
Do not assume tests, builds, migrations, deployment or integrations passed unless execution evidence exists.

## Next tasks
1. Inspect Security Core current files and git history.
2. Run build/typecheck/test commands in an executable environment.
3. Resolve all failures.
4. Complete adversarial security tests.
5. Verify actual wallet/payment route wiring.
6. Move to Risk & Abuse only after Security Core passes.

## Audit update — 2026-09-02

### Completed in this session
- Audited Security Core route wiring and executable checks.
- Restored the API test suite by converting Security Core tests from an unavailable Vitest dependency to the repository's Node test runner.
- Fixed device-proof verification so it validates the presented challenge hash before verifying the device signature, atomically consumes the persisted challenge, and records/increments failures for invalid signatures or unavailable active keys.
- Mapped Security Core validation failures to intentional HTTP statuses.
- Fixed the server startup template literal that prevented TypeScript compilation.
- Restored `PostgresSecurityRepository` conformance with active-device validation.

### Tests actually run
- `npm test --workspace @oppa/api` — passed: 22 tests.
- `npm run api:typecheck` — passed.
- `npm run build` — passed.
- `git diff --check` — passed.

### Remaining next tasks
1. Add route-level/integration tests against a real PostgreSQL test database for concurrent challenge consumption and wallet/payment sensitive-operation wiring.
2. Review the inactive legacy `PostgresSecurityRepository` usage and consolidate security persistence implementations if it is not needed.
3. Continue the Security Core adversarial audit before starting Risk & Abuse.
