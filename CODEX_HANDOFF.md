# OPPA CODEX HANDOFF

## Purpose
Durable resume state for autonomous Codex sessions. The next agent must read this file together with `OPPA_MASTER_BUILD_SPEC.md`, `CODEX_AUTOPILOT.md`, `CODEX_BUILD_MAP.md`, `CODEX_COMPLETE_APPLICATION_TASK.md`, and `CODEX_BACKEND_ADVERSARIAL_AUDIT_TASK.md`.

## LAST UPDATED
2026-09-05 — full remaining V1 work converted into one autonomous completion sprint.

## CURRENT BASELINE

The repository is the implementation source of truth. Historical claims must be re-verified against current source, migrations, tests and the live database where available.

Owner merges application work manually. Do not spend credits on CI, billing or production infrastructure unless required for application correctness.

## IMPORTANT PRODUCT DECISION — LOCKED

**WhatsApp is excluded from OPPA V1.**

OPPA is not WhatsApp and is not affiliated with WhatsApp. Do not implement or expose WhatsApp API/Cloud API integration, account linking, WhatsApp Business onboarding, inbox/sync, WhatsApp-specific models/routes/UI, WhatsApp Web automation/scraping, personal WhatsApp contact/message import or WhatsApp calls in V1.

Future V2 may consider authorized OPPA Business external-channel integrations after fresh provider verification.

## CURRENT IMPLEMENTATION REALITY

The repository contains a substantial TypeScript API foundation including Auth/OTP/Identity, SMS, Device/Session, Profile/Contacts, Messaging, Wallet/Ledger/Transfers, Paystack/Flutterwave payment foundations, Security Core, Risk/Abuse, Notifications/Event Delivery, Business/Merchant and Admin/RBAC/Emergency Controls.

The live OPPA Supabase project has migrations through `0018_harden_public_database_privileges`, with 34 public tables and RLS enabled on those tables. Public `anon`/`authenticated` table privileges were explicitly revoked by migration 0018. The Supabase advisor currently reports INFO-level `rls_enabled_no_policy` notices; the backend audit must establish whether this deny-by-default privileged-backend architecture is intentional and safe, rather than blindly adding policies.

Historical tests are not current proof and must be re-run.

## EXACT NEXT TASK

Run `CODEX_COMPLETE_APPLICATION_TASK.md`.

This is now a **one-session autonomous V1 completion sprint**. Start with the backend adversarial audit and then continue without owner confirmation through all remaining V1 stages:

1. Backend adversarial/security/integration closure
2. Auth + Identity closure
3. Device + Session closure
4. Messaging completion
5. Wallet closure
6. Payments closure
7. Security Core hardening
8. Risk + Abuse completion/wiring
9. Notifications + Event Delivery
10. Admin / Control Center
11. Business / Merchant
12. OPPA-native Calls
13. Flutter mobile application
14. Africa-first offline/network/data resilience
15. Web/Admin/Trust/support surfaces
16. Operations + Launch QA
17. Final V1 acceptance audit

Do not stop after the security audit. When one verified module is finished, immediately continue to the next unfinished module in the same session.

## AFRICA-FIRST PRODUCT REQUIREMENT

OPPA must be engineered for unstable/slow/expensive connectivity and lower-end Android devices.

Treat these as V1 requirements:
- durable local state where appropriate;
- outbound queue for retryable operations;
- reconnect/synchronization;
- exponential backoff with jitter;
- idempotent retries;
- compact payloads/pagination;
- limited polling;
- loading/pending/failed/offline/reconnecting states;
- data-saving mode;
- cache/storage controls;
- media compression/thumbnails/resumable transfer where applicable;
- no false financial success while offline or uncertain;
- low-memory/battery-conscious mobile behavior;
- calls with adaptive bandwidth behavior and audio-first fallback.

## UI / FLUTTER NOTE

Codex is authorized to build and wire the Flutter UI where repository specifications/design direction are sufficient. It must use the OPPA design system and themes (Fluid Africa, OPPA Pulse, Everyday OPPA), build reusable components/tokens and connect screens to real APIs.

Codex must not falsely claim pixel-perfect parity with an owner-approved design when no such design artifact exists. If exact Figma/screenshots are later supplied, the UI can be refined against them.

The Flutter application must be functional, connected and offline-aware, not static mock screens.

## DATABASE / SECURITY NOTE

Audit the actual database and access model. Pay special attention to:
- default privileges for future objects;
- RLS/no-policy architecture;
- exposed Data API access;
- views/functions/security context;
- business/order/product cross-tenant integrity;
- constraints, foreign keys and indexes;
- migration drift.

Do not blindly add RLS policies that conflict with the privileged backend access architecture.

## VERIFICATION RULE

For every module, inspect source/interfaces/migrations/routes/tests; implement the vertical slice; audit authentication, authorization, ownership, replay, idempotency, concurrency, abuse, error leakage and secrets; run targeted/full tests where practical; run typecheck/build/lint/static/schema checks; inspect final diffs; and update this handoff.

Never claim a test, migration, integration, provider capability, call, offline flow or mobile build passed unless actually verified.

## CREDIT / SESSION STOP PROTOCOL

If credits/context/time/environment capacity run out:

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

Never leave the next session guessing where to resume.

## OWNER MERGE POLICY

Owner performs merges manually. Do not force merges or bypass security/quality gates. Do not spend credits on billing, CI/infrastructure or production credentials unless required for application correctness.
