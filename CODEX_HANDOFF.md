# OPPA CODEX HANDOFF

## Purpose
Durable resume state for autonomous Codex sessions. The next agent must read this file together with `OPPA_MASTER_BUILD_SPEC.md`, `CODEX_AUTOPILOT.md`, `CODEX_BUILD_MAP.md` and the active task file.

## LAST UPDATED
2026-09-08 (session 6, OPPA ID + one-identity workspace architecture) — implemented from the updated `CODEX_V1_RELEASE_CANDIDATE_TASK.md`. **Backend — OPPA ID**: migration `0020_oppa_id.sql` (citext unique handle, 3–32 chars, `^[a-z][a-z0-9_]*$` starting with a letter, reserved product/system names unclaimable, nullable — phone-only identity stays valid, change rate-limit table + audit event); `ProfileRepository`/`PostgresProfileRepository` + profile routes `GET /profile/oppa-id/available/:id` (never reveals who holds a taken id), `POST /profile/oppa-id` (auth, server-side validation, per-instance rate limit → `OPPA_ID_RATE_LIMITED` 429), `GET /profile/oppa-id/lookup/:id` (minimal public identity only); 4 new adversarial route tests (`profile-oppa-id.test.ts`). **⚠ Migration 0020 NOT APPLIED to the live DB** — `DATABASE_URL` still absent in this sandbox (same blocker as session 3); the owner must run `bun run migrate` where the DB is reachable. **Mobile**: workspace architecture — Business is NO LONGER a consumer tab; personal shell is Home / Chats / Wallet / Me with a workspace switcher (Home app-bar + Me screen) listing Personal + all the user's businesses; switching opens the separate BusinessApp full-screen and never logs out; `ProfileRepository.oppaIdAvailable/setOppaId/findByOppaId`; Me screen OPPA ID editor (live availability check, honest error surface); Connect accepts `@handle` or bare handle and resolves it via lookup before adding (also still accepts phone/user id); **voice-assisted business onboarding** (`_BusinessNameDialog`): Type/Speak segmented control, tap-to-talk, partial+final transcription, TTS read-back, editable confirmation — mirrors the consumer name flow. Verification: flutter analyze 0 issues; flutter test 19/19 PASS; API 126 pass / 8 skip (DB-integration, need DATABASE_URL) / 0 fail; `tsc --noEmit` PASS. Previous: **Business app built as its own surface** (owner instruction: not the consumer UI with merchant buttons added). `apps/mobile/lib/ui/screens/business_app.dart` (~1470 lines): own NavigationBar (Dashboard / Orders / Products / More), dashboard with revenue hero + metrics + quick actions + recent orders (real `GET /business/:id/analytics` + orders list; customer count derived from real orders), products management (add via dialog → `POST /business/:id/products` with naira→minor conversion; server validates), orders with status filter chips (All/Unpaid/To fulfill/Fulfilled/Cancelled), explicit confirm dialog → fulfill (`POST /business/orders/:id/fulfill`), merchant order details with per-state explanations (merchants never cancel customer orders — server-enforced, stated in UI), **Staff & Roles** (roster + owner-only role change), **Customers** (derived from real orders, spend per customer), **Analytics** (ordersTotal/ordersPaid/revenueMinor with honest revenue definition), **Money & payouts** (instant wallet settlement is real; bank payouts honestly marked "not available yet" — no fake payout success), consumer Business tab now launches the Business app via "Open Business app". **Backend additions** (verified, not just written): `GET /business/:id/staff` (staff-roster, membership-gated, phones masked `+23480****678`) and `PATCH /business/:id/staff/:userId` (owner-only via `for update` row locks inside a transaction, owner row immutable, self-change blocked, audit event `business.staff_role_changed`); +2 route-level adversarial tests (roster masking/denial; owner-only role validation incl. `owner` role value rejected and ghost target 404). **Voice onboarding finalized**: speak → transcription now **editable in place** (enabled field, helper "Is this right? Tap to correct it", clear button) → confirm/skip button label reflects state — matches approved UI flow. Old inline merchant screens removed from `me_screens.dart`. Verification: flutter analyze 0 issues; flutter test 19/19 PASS; API 122 pass / 8 skip (DB-integration, need DATABASE_URL) / 0 fail; `tsc --noEmit` PASS.

Previous: 2026-09-08 (session 4, UI/UX build from approved designs) — Mobile UX feature set completed from the owner's approved UI designs: voice-dictated onboarding (phone → OTP → spoken-name profile step), OPPA Translator (mic → offline phrasebook → TTS playback → send-to-chat), chat thread voice-to-text + per-message translate/read-aloud, full Notifications screen (mark one/all read, unread count, real preferences API) and a Settings screen (language chips, notification toggles via PUT /notifications/preferences, data-saving, themes). New core services: `voice_service.dart` (on-device STT/TTS with honest unavailability states) and `translation_service.dart` (offline phrasebook in en/ha/yo/ig/pcm/fr — dictionary, not machine translation; UI never fakes an untranslated phrase). Home gained Translator/Settings quick actions.

Previous: 2026-09-07 (session 3, `CODEX_FINAL_DB_FIRST_HARDENING_TASK.md`) — DB-first hardening executed to the maximum extent this environment permits. **Live-DB access is BLOCKED** (no `DATABASE_URL` in the sandbox; `freebuff-env`/`freebuff-deploy env list` empty; the Supabase db host resolves IPv6-only and raw v4 egress to it is unavailable). All repo-side deliverables shipped: migration `0019` (call invariant, cross-business FK, grants/RLS), real-Postgres concurrency tests, endpoint-aware retries, lossless offline queue, mobile fulfill/cancel UI, admin report triage. Committed and pushed.

Previous: 2026-09-07 (session 2) — V1 product-gap closure session: order fulfillment + cancellation shipped end-to-end (API + tests), consumer Shop checkout and a real incoming/outgoing call screen added to the Flutter app; all commits pushed to GitHub (`17c21c4`).

## SESSION 3 SUMMARY (DB-first hardening)
- date: 2026-09-07
- starting commit: `98c16ac`
- ending commit: (this commit)
- **Live DB: NOT TOUCHED, NOT VERIFIED.** What was attempted and exactly what blocked it:
  - `DATABASE_URL` absent from shell/process env (`bun -e` with the repo's own pool prints `DB_NULL`); direct env reads are blocked by the platform by design.
  - `freebuff-env` CLI: no list/get verb; `freebuff-deploy env list` returns `{keys: []}`.
  - No `.env` files exist in the repo or `apps/api` (only `.env.example`).
  - Network: the sandbox has IPv6 HTTP egress but `db.bqsovaxbjvgkdnwphprx.supabase.co` has **no A record** (AAAA only); raw TCP from this environment to it is unreachable; regional poolers resolve but the project's pooler hostname has no A record either. Without the credential, connecting is impossible regardless.
  - Consequence: migrations 0018/0019 are NOT applied to the live DB from here; the calls-tables drift and every DB verification step remain the OWNER's one-command action (below). Nothing was faked.
- **Migration 0019 (`database/migrations/0019_db_hardening.sql`) written** (idempotent, requires 0018, transactional):
  1. One non-terminal call per conversation: partial unique index `oppa_calls_one_live_per_conversation_uidx on oppa_calls(conversation_id) where status in ('ringing','active')` — DB-enforced, race-proof; warns instead of failing on pre-existing duplicates.
  2. Cross-business order-item integrity: unique index on `products(id, business_id)` + composite FK `(product_id, order_id) → products(id, business_id)`; a data pre-check ABORTS the migration (transactional) if historical cross-business rows exist, so nothing is silently deleted or skipped.
  3. Grants/default privileges: revokes any anon/authenticated grants on oppa_% tables/sequences; ALTER DEFAULT PRIVILEGES so future objects are not auto-exposed to the Data API roles; re-affirms RLS on every oppa_% table and `schema_migrations`; RLS stays deny-all (no policies) preserving the privileged-backend architecture — no fake auth.uid() policies.
- **Real-Postgres regression tests** (`apps/api/src/db-hardening.test.ts`, run only with DATABASE_URL, self-cleaning): concurrent double startCall → exactly one wins, loser gets unique violation; ended call frees the slot; cross-business item insert → FK violation; same-business item still inserts; every oppa_% table has RLS on and zero policies. Currently skipped (8 skip) without env — never reported as passing.
- **Endpoint-aware retries** (Flutter `api_client.dart`): `retrySafetyFor()` classifies every request; ambiguous network/timeout failures are retried ONLY for reads/deletes/puts/keyed POSTs (message sends via clientMessageId, order pay/fulfill/cancel single-transition endpoints, step-up challenge). `/payments/initialize`, `/wallet/transfer`, `/auth/*`, business/product creation are NEVER blindly retried. Bounded backoff+jitter preserved. 6 unit tests.
- **Lossless offline queue** (`outbound_queue.dart`): explicit state model pending/retrying/blocked/failed. Full queue now THROWS instead of evicting the oldest message; 4xx keeps the op as blocked; exhausted retries keep it as failed; user `retry()`/`discard()` are the only paths in/out; failed state survives restart and never auto-flushes; financial kinds still rejected at enqueue. 4 new tests (9 total for the queue).
- **Mobile order lifecycle completed**: `fulfillOrder`/`cancelOrder` in BusinessRepository; merchant Orders screen shows a Fulfill action on paid orders; Shop screen shows the customer's own orders with cancel-on-pending chips.
- **Admin report triage** (found missing: reports were write-only): `GET /admin/reports` (status+limit validated) and `POST /admin/reports/:id/status` — fraud.review permission, reason shown is user-supplied evidence, never message content.
- OTP honesty: repo scan confirms no bypass/master code/universal OTP exists and none was added; BulkSmsProvider fails closed without `BULKSMS_API_TOKEN`. OTP delivery remains **BLOCKED** on the missing provider credential.
- Call media honesty: lifecycle/signaling is complete and tested; WebRTC offer/answer/ICE negotiation and real audio/video remain **NOT VERIFIED** (needs real device + permissions + TURN); signaling payloads bound by 32kb body cap and member checks; no SDP/ICE credential logging (payloads are stored, not logged).

## STAGE R SESSION SUMMARY (2026-09-07)

## SESSION 2 SUMMARY (2026-09-07, product-gap closure)
- date: 2026-09-07
- starting commit: `3f94167` (Stage R handoff docs)
- ending commit: `17c21c4`
- Baseline re-verified first: API 117 pass / 5 skip / 0 fail, `tsc --noEmit` PASS, Flutter analyze 0 issues, Flutter 7/7 tests, cross-runtime crypto contract PASS (`node scripts/verify-device-key-contract.js`).
- Real gaps found by inspection (not docs) and CLOSED:
  1. **Order lifecycle was stuck at `paid`.** `OrderStatus` includes `fulfilled`, analytics counted it, the DB check constraint allows it — but no code path ever produced it. Added `POST /v1/business/orders/:orderId/fulfill` (any staff of the business; transactional, row-locked, role re-checked INSIDE the transaction, idempotent on already-fulfilled, rejects pending/ended states, audited, notifies the customer via outbox) and `POST /v1/business/orders/:orderId/cancel` (owning customer only, pending only — paid orders can never be cancelled because refunds are deliberately out of scope and cancellation must never move money).
  2. **Consumer checkout was repository-only.** `placeOrder/payOrder` existed in the mobile `BusinessRepository` but no screen used them. Added the Shop flow in Connect (browse a business id → product list with prices → confirm → `placeOrder` with a unique `customerOrderReference` → `payOrder` from wallet; honest error surface incl. `WALLET_INSUFFICIENT_FUNDS`; amounts are always server-derived).
  3. **Calls could be started but never answered.** The chat thread only showed "Calling…". Added `CallScreen` (lib/ui/screens/call_screen.dart): caller + callee phases (ringing/connecting/active/ended), 2s offset event polling with a `sinceSeq` cursor (reconnect-safe), answer/decline(+busy)/hangup against the real endpoints, invite-based incoming-call pickup when opening a conversation (`/calls` history + invite event), cancel for the ringing caller, best-effort hangup on dispose backed by the server's 2-minute ring timeout.
- Tests added: API route attacks (staff-only fulfill 403 vs 200; stranger cancel 404; paid-order cancel 409 `BUSINESS_ORDER_STATE_INVALID`) and 2 Flutter widget tests driving `CallScreen` against a scripted double that mirrors the real API response shapes (callee answer→Connected→End; caller ringing→Cancel).
- Updated handoff note: the earlier "mobile Business tab is a shell" entry was STALE — onboarding/products/orders/analytics UI already existed; only fulfillment + consumer checkout were missing.

## STAGE R SESSION SUMMARY (2026-09-07)
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

## VERIFIED (session 3, 2026-09-07)
- tests: PASS — 120 pass / 8 skip / 0 fail (`bun test src` in apps/api; the 8 skips are Postgres integration tests incl. the 3 new DB-hardening tests, all requiring `DATABASE_URL`).
- typecheck: PASS — `tsc --noEmit` (strict)
- build: PASS — `bun run build` emits dist/server.js (dist removed after verification)
- flutter analyze: PASS — `No issues found!`
- flutter test: PASS — 19/19 (offline_queue 8, crypto_contract 3, call_screen 2, retry_policy 6)
- cross-runtime crypto contract: PASS — `node scripts/verify-device-key-contract.js`
- lint/static: scans clean (no TODO/FIXME/stub/501; no OTP bypass; no secrets; no fake success paths)
- migrations 0018+0019 on live DB: **NOT APPLIED / BLOCKED** — no `DATABASE_URL` in this environment (attempts documented in SESSION 3 SUMMARY); never claimed applied
- integration (real Postgres): **BLOCKED** — 8 integration tests written and ready, not run
- Android build / real device: **BLOCKED** — no Android SDK or device here
- OTP delivery: **BLOCKED** — provider credential missing; no bypass exists or was added
- Call media (real WebRTC audio/video): **NOT VERIFIED** — signaling/lifecycle tested server-side and in widget tests; media needs real devices

## NEXT EXACT TASK (owner actions, in order)
1. Put the live Supabase `DATABASE_URL` into the verification environment (Settings → Environment / deploy env), then run exactly:
   `cd apps/api && bun run migrate` (applies 0018 → fixes the missing oppa_calls/oppa_call_events drift → then 0019 adds the call invariant, cross-business FK and grants hardening; if any cross-business order rows exist it aborts with a count instead of corrupting anything)
2. `cd apps/api && bun test src` — the 8 integration tests (5 security-core + 3 DB-hardening) run for real; record results.
3. Re-run the Supabase advisor; the only acceptable findings are the intentional deny-all-RLS-with-no-policies posture and PostgREST exposure notes.
4. Android: import `apps/mobile` into an Android-capable environment, `flutter build apk --release`, run the Stage R §5 acceptance list. OTP delivery needs `BULKSMS_API_TOKEN` (and OTP secrets) to be set, or OTP stays BLOCKED and post-auth flows need a test session.

## PREVIOUS SESSION 2 NOTES (kept for context)

## NOT DONE
- Real-device call media validation (WebRTC client-to-client path) requires two physical/virtual devices with cameras/mics — signaling layer complete and tested server-side; media is standard WebRTC per documented assumptions.
- Provider refunds (Paystack/Flutterwave) remain intentionally unadvertised; requires real provider API verification.
- Push notifications (FCM) — V1 ships in-app notifications; push transport is a deliberate follow-up.
- RLS policy hardening beyond `enable row level security` — access model is privileged-backend; documented, not changed.

## KNOWN FAILURES/RISKS
- Without `DATABASE_URL`, nothing here proves runtime behavior against Postgres; apply migrations and run the 5 integration tests first in any verified environment.
- Call signaling relies on client polling cadence; clients must back off on errors (documented in calls-routes/calls-service) to avoid battery/network waste.
- Stage R webhook attack suite and journey test use stateful in-memory fakes that mirror the Postgres predicates 1:1 (row locks, consume-once, provider-scoped lookups); real-Postgres confirmation remains gated on `DATABASE_URL`.

## NEXT EXACT TASK (session 2 — superseded by session 3's task list above)
1. On an environment with `DATABASE_URL`: `cd apps/api && bun run migrate` (applies 0001–0018) then `bun test src` (runs the 5 integration tests + all attack/journey tests against real persistence). Record results.
2. On a machine with the Android SDK: `cd apps/mobile && flutter build apk --release`, install on a device, and run the Stage R real-device acceptance list in `CODEX_V1_RELEASE_CANDIDATE_TASK.md` §5.
3. Optionally add FCM push transport behind the existing notification outbox (delivery adapter pattern is in place).

## MANUAL OWNER ACTION
- Provide `DATABASE_URL` (and auth/session/payment secrets) in the verification environment.
- Build/sign the Android APK in a Flutter+Android-SDK environment for store distribution and run the real-device acceptance list.

## V1 EXECUTION ORDER — STATE (updated session 2)
1. Auth/Identity closure — DONE (login risk gate closed)
2. Device/Session closure — DONE
3. Messaging — DONE (receipts, groups, idempotency; realtime transport remains REST+polling by design)
4. Wallet — DONE (audit-hardened; Stage R journey test added)
5. Payments — DONE (refunds deliberately out of scope, documented; Stage R webhook attack suite added)
6. Security Core — DONE (audit)
7. Risk/Abuse — DONE (login gating wired; reports surface added)
8. Notifications — DONE (durable outbox + reaper)
9. Admin/Control Center — DONE
10. Business/Merchant — DONE (self-order blocker at creation AND settlement; fulfillment + cancellation now complete)
11. OPPA-native Calls — DONE (signaling + lifecycle + abuse controls + mobile call UI)
12. Flutter mobile — DONE at source level, SDK-VERIFIED (analyze 0 findings, 9/9 tests incl. call lifecycle; Android build BLOCKED — no SDK/device)
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
