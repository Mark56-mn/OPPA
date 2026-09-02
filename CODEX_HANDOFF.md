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
