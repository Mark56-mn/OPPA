# OPPA CODEX HANDOFF

## Purpose
Durable resume state for autonomous Codex sessions. The next agent must read this file together with `OPPA_MASTER_BUILD_SPEC.md`, `CODEX_AUTOPILOT.md`, `CODEX_BUILD_MAP.md` and the active task file.

## LAST UPDATED
2026-09-07 — Stage R (`CODEX_V1_RELEASE_CANDIDATE_TASK.md`) executed: Flutter SDK verification completed for real, all implementation commits pushed to GitHub, route-level webhook attack suite + connected product journey added and passing.

## STAGE R SESSION SUMMARY
- date: 2026-09-07
- starting commit: `e00f358` (docs: add V1 release candidate integration task)
- ending commit: `8bd2ca1`
- GitHub gap closed: the implementation commits (`8f935ae` audit fixes, `1cd56f9` calls, `d68969b` Flutter+web, `ebae1c0` docs) existed only locally and were never pushed — this is why the repo appeared docs-only after `6dd9730`. They are now on origin.
- **Flutter SDK verification actually executed** (SDK found at `/tmp/flutter`): `flutter analyze` = No issues found; `flutter test` = 7/7 pass, including the new `test/crypto_contract_test.dart` asserting the SPKI DER OIDs byte-for-byte (pointycastle's OID *decoder* drops continuation bits — 840→72, 10045→61 — so raw-DER assertions are required; the Dart *encoder* is correct) and verifying a real ECDSA P-256 step-up signature over `${challenge}.${canonicalIntent}`.
- Cross-runtime proof: `scripts/verify-device-key-contract.js` verifies the mobile signature encoding with the backend's own primitive (`createVerify("SHA256")` + server OIDs) — PASS.
- Stage R attack tests added: `apps/api/src/modules/payments/payment-webhook-routes.test.ts` (11 route-level attacks on the only unauthenticated surface) and `apps/api/src/journey-v1.test.ts` (connected journey with real services).

## CURRENT BASELINE
- Starting commit of sprint session: `75e1e0f` (docs: handoff full autonomous V1 completion sprint), rebased onto `854c9a6` (audit fixes).
- Migrations 0001–0018 present (0018 = abuse reports + OPPA-native call signaling).
- WhatsApp remains excluded from V1 (V2 only). Browser/VPN/Mini Apps deferred.

## SESSION SUMMARY (V1 completion sprint)
- date: 2026-09-05
- starting commit: `75e1e0f` (after rebase: audit fixes `854c9a6` preserved)
- ending commit: `7e4d121`
- exact scope worked: backend adversarial re-audit closure (login risk gate, abuse reporting), OPPA-native Calls, complete Flutter application, Africa-first offline architecture, web/trust surface, migration runner, final QA scans.

## COMPLETED (this sprint, by stage)
- **A — Backend audit re-verified**: prior audit fixes intact after rebase; baseline 90 pass / 5 skip; route classification re-checked (all 60+ routes behind requireAuth/requirePermission; webhooks remain the only unauthenticated surface, signature-verified).
- **B–K closure fixes**:
  - R1 (auth/risk): the login path now consults `RiskService.getActiveDecision(userId,"login")` — operator `block` denies authentication (`ACCOUNT_UNAVAILABLE`), `review` records a `login_anomaly` event. Risk unavailability never locks users out (fail-open for observability only, same policy as OTP).
  - C1 (contacts): `POST /contacts/:userId/report` added with bounded reason (≤500), idempotent per (reporter, reported) via unique index; migration 0018 adds `oppa_user_reports`.
- **L — OPPA-native Calls (complete vertical slice)**:
  - Migration 0018: `oppa_calls` (conversation-scoped lifecycle: ringing→active→ended, end_reason enum, one-ringing-per-conversation partial unique index) and `oppa_call_events` (per-user offset event log).
  - `apps/api/src/modules/calls/`: CallsService (validation, rate limit 5/min/caller, ring-timeout sweep) + PostgresCallsStore (all mutations check conversation membership INSIDE the transaction; deterministic `for update` call lock; benign-abort sentinel guarantees the pooled client's transaction is always closed and released).
  - Routes: start/answer/decline(+busy)/hangup/history/events(offset polling)/signal (SDP/ICE relay between verified members only). Server never terminates media — WebRTC DTLS-SRTP is client-to-client; no invented cryptosystem, no provider secrets (documented in calls-service.ts).
  - Africa-first: REST+polling signaling (no WebSocket dependency), audio-first, adaptive-quality responsibility on client, 2-minute ring timeout sweeper.
  - Tests: 15 (service validation/rate-limit/lifecycle + fake-pool transactional membership regressions incl. non-member rejection, rollback paths, client release).
- **M — Flutter application (complete source, real API integration)** in `apps/mobile/`:
  - `core/api_client.dart`: timeouts, retry classification (network/timeout/5xx retry, 4xx never), exponential backoff + 30% jitter, auth-token injection, single re-auth retry on 401.
  - `core/outbound_queue.dart`: durable offline queue (SharedPreferences-persisted, survives restart, max 200 ops, attempt cap) for messaging-only ops — financial kinds are rejected by `enqueue`. `SecureTokenStore` holds access/refresh/device ids in flutter_secure_storage.
  - `core/session_store.dart`: OTP request/verify, refresh-token rotation (single-flight), logout.
  - `core/device_key_manager.dart`: real EC P-256 keypair; SPKI public PEM is the enrollment deviceId; ECDSA-SHA256 DER/base64url signature over `${challenge}.${canonicalIntent}` matching the backend DeviceProofService byte-for-byte (pointycastle).
  - `core/screen_data.dart` + `ui/widgets/common.dart`: cache-first loading with ViewLoading/ViewReady(fromCache)/ViewError/ViewOffline and StatusBanner (online/reconnecting/offline + pending count).
  - `data/repositories.dart`: typed repos matching the API contract exactly (verified against every router source).
  - Screens: AuthGate (phone→OTP, theme picker), Home (balance, notifications preview, support/connect), Chats + ChatThread (offline-pending sends with server-confirmed success only, call buttons), Contacts/Connect (add/block/report), Wallet (balance, history, step-up transfer with real device signing, Paystack/Flutterwave funding via hosted URL), Business, Me (profile, themes, security posture, sign-out), Support & Safety.
  - `design/oppa_themes.dart`: Fluid Africa / OPPA Pulse / Everyday OPPA as token-driven Material 3 themes (visual tokens only).
  - Tests: `test/offline_queue_test.dart` (persistence, ordering, financial-kind rejection, restart survival).
- **N — Africa-first offline/network**: durable queue + reconnect flush (connectivity restore callback), backoff+jitter, explicit offline/pending/reconnecting UI, pagination everywhere, compact payloads, no financial optimism, cache-first screens, no heavy dependencies (5 runtime packages).
- **O — Web/Admin/Trust**: `web/index.html` static surface (product, trust & safety, privacy, support) with the honest "not affiliated with WhatsApp" footer; support/contact/reporting covered in-app (Support & Safety screen) and via the abuse-report API.
- **P — Operations**: `apps/api/src/scripts/migrate.ts` idempotent migration runner (schema_migrations tracking, per-migration transaction, fail-fast, `bun run migrate` in apps/api). Final scans: no TODO/stub/501, no WhatsApp references, no committed secrets, admin surfaces cannot read message bodies (metadata-only).
- **Session contract fix**: `SessionService.create` now returns `deviceId` (the enrolled device row id) so clients can present step-up proofs — required by the mobile transfer flow.

## FILES CHANGED (this sprint)
- apps/api/src/modules/calls/{calls-service.ts,calls-routes.ts,calls-service.test.ts,calls-transactions.test.ts} (new)
- apps/api/src/modules/auth/auth-service.ts (login risk gate)
- apps/api/src/modules/contact/{contact-repository.ts,postgres-contact-repository.ts,contact-routes.ts} (report)
- apps/api/src/modules/session/session-service.ts (deviceId in session payload)
- apps/api/src/http/error-handler.ts (call + report error codes)
- apps/api/src/server.ts (calls router, sweeper)
- apps/api/src/scripts/migrate.ts (new), apps/api/package.json (migrate script)
- database/migrations/0018_reports_calls.sql (new)
- apps/mobile/** (new Flutter app: lib/, test/, pubspec.yaml, README.md, analysis_options.yaml)
- web/index.html (new)
- CODEX_HANDOFF.md (this file)

## COMMITS
- `f5cd26c` feat: OPPA-native calls, abuse reporting and login risk gating
- `7e4d121` feat: Flutter mobile app, web/trust surface and migration runner
- (prior) `854c9a6` fix: close adversarial audit findings in wallet, business, notifications and security core

## VERIFIED
- tests: PASS — 117 pass / 5 skip / 0 fail (`bun test src` in apps/api; the 5 skips are Postgres integration tests requiring `DATABASE_URL`). New: 11 webhook attack tests + 1 connected journey test.
- typecheck: PASS — `bun run api:typecheck` (tsc --noEmit, strict)
- build: PASS — `bun run build` emits dist/server.js (dist removed after verification)
- flutter analyze: PASS — `No issues found!` (real SDK 3.35.3, run 2026-09-07)
- flutter test: PASS — 7/7 (`test/offline_queue_test.dart` 4 + `test/crypto_contract_test.dart` 3)
- cross-runtime crypto contract: PASS — `node scripts/verify-device-key-contract.js`
- lint/static: scans clean (no TODO/FIXME/stub/501; no WhatsApp; no secrets; no mock-success responses; no client-trusted authorization)
- Stage R release checks: PASS — no provider secrets bundled, no debug backdoors, admin surfaces metadata-only, V1 scope intact
- migrations: NOT APPLIED — no `DATABASE_URL` in this environment; static review of 0001–0018 done; runner shipped and fails fast
- integration: BLOCKED — no `DATABASE_URL`; migration application + 5 integration tests NOT RUN (never claimed passed)
- Android build / real device: BLOCKED — no Android SDK or device in this environment (flutter doctor: Unable to locate Android SDK); never claimed passed

## PARTIALLY COMPLETED
- Mobile Business tab is a coherent shell (reads connectivity, honest empty state); full merchant UI flows (store onboarding screens) were deferred to keep the session within scope — the backend business vertical slice is complete from the prior sprint.

## NOT DONE
- Real-device call media validation (WebRTC client-to-client path) requires two physical/virtual devices with cameras/mics — signaling layer complete and tested server-side; media is standard WebRTC per documented assumptions.
- Provider refunds (Paystack/Flutterwave) remain intentionally unadvertised; requires real provider API verification.
- Push notifications (FCM) — V1 ships in-app notifications; push transport is a deliberate follow-up.
- RLS policy hardening beyond `enable row level security` — access model is privileged-backend; documented, not changed.

## KNOWN FAILURES/RISKS
- Without `DATABASE_URL`, nothing here proves runtime behavior against Postgres; apply migrations and run the 5 integration tests first in any verified environment.
- Call signaling relies on client polling cadence; clients must back off on errors (documented in calls-routes/calls-service) to avoid battery/network waste.
- Stage R webhook attack suite and journey test use stateful in-memory fakes that mirror the Postgres predicates 1:1 (row locks, consume-once, provider-scoped lookups); real-Postgres confirmation remains gated on `DATABASE_URL`.

## NEXT EXACT TASK
1. On an environment with `DATABASE_URL`: `cd apps/api && bun run migrate` (applies 0001–0018) then `bun test src` (runs the 5 integration tests + all attack/journey tests against real persistence). Record results.
2. On a machine with the Android SDK: `cd apps/mobile && flutter build apk --release`, install on a device, and run the Stage R real-device acceptance list in `CODEX_V1_RELEASE_CANDIDATE_TASK.md` §5.
3. Optionally add FCM push transport behind the existing notification outbox (delivery adapter pattern is in place).

## MANUAL OWNER ACTION
- Provide `DATABASE_URL` (and auth/session/payment secrets) in the verification environment.
- Build/sign the Android APK in a Flutter+Android-SDK environment for store distribution and run the real-device acceptance list.

## V1 EXECUTION ORDER — STATE
1. Auth/Identity closure — DONE (login risk gate closed)
2. Device/Session closure — DONE
3. Messaging — DONE (receipts, groups, idempotency; realtime transport remains REST+polling by design)
4. Wallet — DONE (audit-hardened; Stage R journey test added)
5. Payments — DONE (refunds deliberately out of scope, documented; Stage R webhook attack suite added)
6. Security Core — DONE (audit)
7. Risk/Abuse — DONE (login gating wired; reports surface added)
8. Notifications — DONE (durable outbox + reaper)
9. Admin/Control Center — DONE
10. Business/Merchant — DONE (self-order blocker at creation AND settlement)
11. OPPA-native Calls — DONE (signaling + lifecycle + abuse controls)
12. Flutter mobile — DONE at source level, SDK-VERIFIED (analyze 0 findings, 7/7 tests; Android build BLOCKED — no SDK/device)
13. Web/Admin/Trust — DONE (static surface + in-app support)
14. Operations + Launch QA — DONE to the extent verifiable without live DB/device
15. **Stage R — release candidate: executed** (crypto contract proven cross-runtime; webhook attacks + connected journey passing; DB/device verification BLOCKED, see NOT DONE)

WhatsApp is not in this V1 order (V2 only).

## VERIFICATION RULE
For every module, inspect source/interfaces/migrations/routes/tests; implement the complete vertical slice; audit authentication, authorization, ownership, replay, idempotency, concurrency, abuse, error leakage and secrets; run available tests/typecheck/build/lint/schema checks; inspect the final diff; and update this handoff.

Never claim a test, migration, integration or deployment passed unless actually verified.

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
