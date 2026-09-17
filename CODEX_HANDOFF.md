# OPPA CODEX HANDOFF

## Purpose
Durable resume state for autonomous Codex sessions. The next agent must read this file together with `OPPA_MASTER_BUILD_SPEC.md`, `CODEX_AUTOPILOT.md`, `CODEX_BUILD_MAP.md` and the active task file.

## LAST UPDATED
2026-09-17 (session 13, **VISUAL + FUNCTIONAL COMPLETION MISSION — ONBOARDING / THEMES / BUSINESS WORKSPACE**, branch `oppa-mobile-demo`) — **Executed the OPPA V1 Visual + Functional Completion Mission against the approved UI reference images: complete 8-step onboarding (incl. real OPPA ID claim), three approved themes that actually persist and render correctly, and a Business workspace whose creation flow genuinely works (it did not before). No fake success anywhere: everything added is either a real server-backed flow or an explicit honest lock.**

**AUDIT FIRST (what the references required vs what existed)**: onboarding was `phone → otp → profile → done` only. Profile photo, "Choose your OPPA ID", "Choose Your OPPA Look" and the security step from the approved art were MISSING; the look picker was buried at the bottom of the phone screen. `themeId` was in-memory (reset on every restart) and `buildOppaTheme` was always called with `Brightness.dark` even for the light "Everyday OPPA" palette — white surface + dark text rendered as an unreadable dark scheme.

**§4 ONBOARDING (now complete, 8 steps)**: Welcome/phone → OTP → profile (Speak/Type segmented voice-name entry, editable transcription, read-back) → profile picture → **Choose your OPPA ID** → **Choose Your OPPA Look** → security → "You're all set!" → Start OPPA.
- OPPA ID is 100% real: three candidates are derived from the spoken/typed name, each checked against `GET /profile/oppa-id/available/:id` in parallel, free-text entry is debounce-checked, and `POST /profile/oppa-id` performs the claim. Continue is disabled until the SERVER says available; a rejected claim (taken in a race / reserved / rate-limited) keeps the user on the step with the server's reason. "Skip for now" is offered. Demo backend now mirrors the production shape/reserved/taken rules so the failure paths are exercisable.
- Profile picture: rendered exactly like the reference (avatar circle + Camera/Gallery), but the API has NO media-upload endpoint in V1 — the buttons open the honest "not in this release" sheet and no fabricated `avatarUrl` is ever written.
- Security step states only what is genuinely true (device really is enrolled by OTP verify; codes are single-use) and marks app-lock PIN / biometrics / 2FA as not shipped.
- New `OppaFeature` locks added: `profilePhoto`, `appLock`, `requestMoney`, `attachments`.

**§5 THEMES (three approved looks, now correct and durable)**:
- REAL BUG: the chosen look reset to the default on every launch. `themeId` is now restored in `initState` from `SharedPreferences` via `ThemePreference` (encode/decode by enum name, unknown value falls back to the default) and persisted on every change. A State field initializer cannot read `widget`, so restoration happens before the first frame (no wrong-theme flash).
- REAL BUG: `OppaTokens` gained a `brightness` field; `buildOppaTheme` now defaults to the palette's own lightness. "Everyday OPPA" is the approved LIGHT look (white surface, dark text) and finally renders as one.

**§8 BUSINESS WORKSPACE ("creating a business must actually work") — ROOT CAUSE FOUND AND FIXED**:
- REAL BUG (demo/APK): the in-process router matched only paths starting with `/business/`, so BOTH `GET /business` (the switcher's list) and `POST /business` (create) fell through to NOT_FOUND. Creation returned nothing and the switcher could not list stores — the workspace was broken exactly as reported. Fixed: the bare `/business` path routes now, and `_getBusiness`/`_postBusiness` were rewritten to be per-business.
- REAL BUG: `GET /business` always returned the single hardcoded seed and every sub-screen ignored the business id, so a newly created store silently inherited another store's catalogue/orders/roster. Now: created businesses are appended to a real list, products/orders/staff/analytics are scoped by `businessId`, a fresh store starts genuinely empty (only its own owner staff row), and an unknown id is a real `BUSINESS_NOT_FOUND` 404.
- REAL BUG (UX): the Business app is a fullscreen route on a nested Navigator with NO way out — a merchant who switched in was stuck. Added an explicit "Back to Personal" close action in the merchant app bar.
- NEW REAL ENDPOINTS (task required "edit product" + "business profile"; neither existed): `PATCH /business/:businessId/products/:productId` (owner/manager; validates name/price/description/status, scoped to the owning business) and `PATCH /business/:businessId` (owner-only rename/re-describe). Repository gained `updateProduct` + `updateBusiness`; `listProducts` gained `includeArchived`, honoured ONLY for staff of that business so customers never see archived rows.
- UI: products screen now lists archived rows for staff with a real archive/restore action, and a shared add/edit sheet (one form, so the two flows cannot disagree); new **Business profile** screen (real read + owner-only edit, app-bar title updates from persisted truth); new **Merchant translator** entry (the same production translator, framed for market/shop owners — hidden, never dead, when messaging is unavailable).
- Merchant chat: order details and the customer list now offer "Message customer", which opens the REAL direct conversation via `POST /conversations/direct` (server-side idempotent). Messaging is a personal capability, so the hand-off leaves the Business workspace, switches to the Chats tab and opens the thread.

**§6/§10 MESSAGING**: NEW **Message Details** sheet wired to the real per-recipient receipts endpoint (`GET /conversations/:id/messages/:messageId/receipts` → `{userId, deliveredAt, readAt}`): Sent / Delivered / Read by with real server timestamps, plus per-recipient rows and an honest privacy note. Tapping the receipt tick on your own message opens it; incoming messages never expose another member's read time. Exposed on `MessagesRepository.receipts()` and implemented in the demo backend (unknown message id ⇒ ZERO rows, never an invented reader).
- Composer now shows the reference's attachment control as an honest lock (no media endpoint in V1).
- Translator "Send to chat" replaced the raw conversation-id text box with a REAL conversation picker (names and unread counts from the server); the in-thread translator now gets the same picker. Before, users had to type a database id.

**§13 WALLET**: approved wallet action row implemented — Deposit (real, payment initialize) · Send (real, challenge → ECDSA device signature → server confirm) · Request (no endpoint in V1, honest lock).

**VERIFICATION (all executed this session)**:
| Gate | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | **70 pass / 0 fail** (+2 by-design skips) |
| `bun run typecheck` (api) | clean |
| `bun test` (api) | **158 pass / 0 fail** / 8 skip |
| `tools/check_brand_assets.py` | PASS (launcher + adaptive + splash OPPA-branded) |
| `codemagic.yaml` | parses; both workflows intact, demo define guard + brand guard run before the APK build |

New tests (all green): `business_workspace_test.dart` (10) — creation persists and is listed, blank/oversized name refused with nothing created, a fresh store inherits no catalogue/orders and exactly one owner staff row, unknown id is a 404, add/edit/archive/restore product with documented error codes, rename persists, direct conversation is idempotent, per-store analytics isolation. `business_ui_test.dart` (3) — full merchant journey: switcher → create → lands in its own workspace with an empty catalogue; the created store is listed on the way back; the stored OPPA Look is restored on launch with the correct LIGHT brightness. `message_details_test.dart` (3) — receipts contract. `startup_ui_test.dart` extended to walk all 8 onboarding steps including the real OPPA ID claim and the taken-name rejection (server-decided, Continue blocked). API: 3 new business tests (product edit incl. invalid price/status/empty patch, staff-only archived listing, owner-scoped profile rename).

**STILL BLOCKED (unchanged, environmental)**: (1) APK build + on-device/emulator verification — no Java/Android SDK here; the Codemagic `oppa-mobile-demo` workflow is wired and runs the same gates (analyze, full test suite, brand guard, demo-define-positive test, then `flutter build apk --debug --dart-define=OPPA_DEMO_MODE=true`). (2) 8 API tests SKIP because `DATABASE_URL` is absent from this session's shell; they pass where the secret exists. (3) Profile-photo upload and attachments are BLOCKED BY DESIGN for V1 (no media service) and are rendered as honest locks, not failures. (4) Real audio/video in calls remains out of scope (no WebRTC client stack; the call screen says so).

**NEXT EXACT TASK**: run the Codemagic `oppa-mobile-demo` workflow on this commit; then on device: (1) confirm the OPPA launcher icon + splash; (2) walk the 8 onboarding steps — speak a name, claim an OPPA ID, pick each of the three looks and confirm Everyday OPPA renders LIGHT, kill and relaunch to confirm the look persisted; (3) Business: switcher → Create a Business → confirm it appears in the list after returning, add/edit/archive a product, rename the store from Business profile; (4) Chats: send a message, tap the receipt tick → Message Details shows real Sent/Delivered/Read times; (5) translator → Send to chat → pick a real conversation. Then merge `oppa-mobile-demo` → `main` per owner policy.

---

## PREVIOUS SESSION (12)
2026-09-16 (session 12, **NEXT-APK V1 COMPLETION PASS — §9/§10/§11/§13/§14/§16 CLOSED**, branch `oppa-mobile-demo`) — **Executed CODEX_NEXT_APK_V1_COMPLETION_TASK.md sections 6/9/10/11/13/14/15/16 to completion: real mark-read receipts end-to-end, honest call states, notification tap-to-context + preferences, server-authoritative wallet with transaction detail, and zero dead navigation. All gates green: flutter analyze clean, 53 mobile tests pass, 155 API tests pass, brand guard passes.**

**§6 Branding (completed this session)**: OPPA Pulse launcher icons (all densities) + adaptive icon (API 26+) + brand launch splash — all rendered procedurally by `tools/generate_oppa_icons.py` from the same orb geometry as the in-app vector painter (no invented art, ~250 KB total). New `tools/check_brand_assets.py` CI guard (wired into BOTH codemagic workflows before the APK builds) fails the build if any Flutter-default launcher icon returns, verified in both directions (OPPA art passes; wrong pin / unparsable default fails).

**§9 Messaging (audit + fixes)**:
- REAL BUG: `MessagesRepository.markRead()` and the API route `POST /conversations/:conversationId/read` existed but NO SCREEN EVER CALLED THEM — unread badges could never clear in production. Fixed: `ChatThreadScreen._load()` now marks read up to the newest incoming message (fire-and-forget, failure never blocks reading; logged via `OPPA.chat:` diagnostics).
- REAL BUG (prod parity): production message history had no `mine` field (demo had it) so bubble alignment broke in production. Fixed server-side: the messages route projects `mine` per caller (never leaks identity beyond sender id).
- Read receipts now rendered honestly on own bubbles: clock = pending, one check = sent, double-check = read. Backed by a new server-computed `readByAny` field (postgres: EXISTS any OTHER member's receipt with read_at) — nothing fabricated client-side.
- Scroll-to-top pagination wired: `_onScroll` fetches older pages with the existing `before` cursor (dedup by id, stops honestly on short page/server refusal). No data loss on fetch failure.
- Tests: new `chat_mark_read_test.dart` (recording transport asserts the exact POST /read call + upToMessageId = newest incoming; negative case: no incoming → no request). API test added: message-history ownership projection (`m-from-other`→false, `m-from-me`→true).

**§10 Notifications (audit + fixes)**: category filters (All/Messages/Payments/System per the approved art), tap-to-context routing (message → its conversation thread via metadata.conversationId; business → Business workspace; payment/wallet → Wallet tab; security/device → Devices; support → Help) — personal taps never open business context. Preferences rows persisted via the real preferences endpoint. Demo backend now seeds deterministic notifications across ALL SEVEN production categories (message/payment/wallet/business/security/device/support) with production payload contract `{category,title,body,metadata,createdAt}` + readAt — the demo notification screen was previously ALWAYS EMPTY, making §10 untestable in the demo APK. Seeded conversationId fixed to a real demo conversation.

**§11 Calls**: lifecycle verified real (invite/answer/decline/busy/hangup/failed via server events; 2s polling; safe auto-hangup on back-out). REAL §11 VIOLATION FIXED: the call screen said "Connected" and showed fake media copy ("Media quality adapts…") while the app has NO WebRTC client stack (backend signaling relay exists; no flutter_webrtc dependency). Now honest: "Call answered — audio media coming in a later release" + explicit note that ring/answer/decline/hang-up are real and server-confirmed but NO audio is transmitted. Video remains visible-but-locked (matches V1 capability). Test updated to assert the honest string.

**§13/§16 Wallet + offline**: balance card now labels cached data honestly — "Last known balance (offline) / Will update when you reconnect" (ScreenDataSource already tracked fromCache; the UI ignored it). Transaction list rebuilt on the PRODUCTION field contract (type credit|debit, amountMinor, balanceAfterMinor, reference, description, createdAt) — the demo was emitting demo-only keys (direction/status), a parity bug. NEW transaction detail bottom sheet: money-in/out, balance-after, reference, date, "Confirmed by the OPPA server" — read-only, zero invention. Bank Transfer/USSD remain visible-but-locked. Transfers keep the real challenge → ECDSA device-signature → server confirmation chain; nothing queued or faked offline.

**§14/§15 Business + settings**: business More rows verified live (staff/customers/analytics/payouts/support all real screens on real endpoints). DEAD BUTTON FIXED: the business app-bar refresh icon was `onPressed: () {}` — now triggers the dashboard's real fetch via a registered callback (same pattern as chats refresh). No product edit/delete buttons exist because no such endpoints exist server-side (honest by construction). Merchant cannot order against own business (server-enforced, documented in repositories.dart).

**Verification (all executed this session)**:
| Gate | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | 53 pass / 0 fail (+2 by-design skips) |
| `bun run typecheck` (api) | clean |
| `bun test` (api) | 155 pass / 0 fail / 8 skip |
| messaging+wallet suites | 14/14 incl. 2 new tests |
| `tools/check_brand_assets.py` | PASS (launcher+adaptive+splash OPPA-branded) |

**BLOCKED (unchanged, environmental)**: (1) APK build/on-device verification — no Java/Android SDK/emulator in sandbox; Codemagic workflow is wired and will run the same gates. (2) 3 DB-hardening + 5 auth-integration API tests SKIP because `DATABASE_URL` is not present in this session's shell (task §17's live-DB checks need it; they pass when run where the secret exists). No other provider is blocking.

**NEXT EXACT TASK**: (1) run the Codemagic `oppa-mobile-demo` workflow; verify Analyze/Unit tests/brand-guard/define-positive steps all green and the APK artifact downloads; (2) install on device: launch → AuthGate; logcat `OPPA.session:` shows signedOut; demo phone → 000000 → profile → Home; open Amara thread → back → badge cleared (mark-read on device); Wallet shows Last-known-balance label in airplane mode; call screen shows the honest "no audio transmitted" note; (3) after the device pass, merge `oppa-mobile-demo` → `main` per owner policy.

---

## PREVIOUS SESSION (11)
2026-09-15 (session 11, **UI ALIGNMENT TO OPPA PULSE REFERENCE + ANDROID VOICE FIXES**, branch `oppa-mobile-demo`) — **UI realigned to the approved OPPA Pulse reference boards (both uploaded sheets) with a vector brand kit, honest V1 feature locks, and the Android speech-capability failures fixed at the capability layer. No generated/approximated images: the OPPA Pulse orb is drawn in code (`CustomPaint`), keeping the APK lightweight (zero new image assets).**

**Brand + theme (approved identity)**:
- New `apps/mobile/lib/design/oppa_brand.dart` — `OppaPulsePainter` (glowing sphere + three woven light trails: blue/violet, magenta, amber), `OppaBrand.wordmarkBlock`, gradient constants. Pure vector; the splash/brand screens render the actual mark from the reference.
- `oppa_themes.dart` token sets re-aligned to the "Choose Your OPPA Look" art: **OPPA Pulse** = brand violet on near-black (default look), **Fluid Africa** = warm amber/gold on deep brown, **Everyday OPPA** = clean green on white. Theme builder now also themes cards/dialogs/bottom-sheets (16–24px radii per the reference).

**Onboarding rebuilt to the approved journey** (`auth_gate.dart`):
Welcome (orb + "OPPA PULSE" + slogan) → phone (+234, honest OTP microcopy) → OTP (masked number, live "Resend code in 00:XX" countdown, friendly error mapping) → "Create your profile" (Type/Speak segmented control, tap-to-speak, **editable transcription**, spoken read-back) → **"You're all set!"** confirmation ("Your OPPA account is ready. Let's get you connected." + Start OPPA + Explore OPPA) → Home. The name is saved in `completeOnboarding()` when Start OPPA is tapped, so the confirmation step is genuinely visible. Theme picker ("Choose Your OPPA Look") lives on the welcome step with the approved look names.

**Navigation aligned to the personal-app art** (`screens.dart`): bottom tabs are now **Chats · Wallet · Calls · Me** (was Home/Chats/Wallet/Me). Chats tab gained the reference header: search field + All/Unread/Groups/Businesses filter chips, full-screen search, translator shortcut, workspace switcher, new-chat FAB. Calls tab is new (`CallsTabScreen`): one-tap voice calls per conversation over the real REST signaling lifecycle; video stays visible-but-locked. Me tab is the approved "My Profile" page: avatar/name/phone header, Edit profile, Notifications/Settings/Help & Support rows, Devices & Sessions, locked 2FA/biometrics/storage rows, Appearance (look names + locked 4th look), Sign out. Workspace switcher consolidated into `workspace_switcher.dart` (single shared sheet; duplicates removed). The orphaned HomeScreen tab was removed with its duties moved to Me/Chats (Connect + Translator + Support + Notifications + Settings + Business switch all reachable from real UI).

**Real data-shape bug fixed (prod parity)**: production conversations return `unreadCount` (postgres-conversation-repository.ts); the demo backend returned `unread`, so chat badges could never appear. Demo now returns `unreadCount` and the UI reads exactly that field (parity test added).

**Locked-feature system** (`design/locked_features.dart`): `OppaFeature` enum with honest, plain-language explanations; `LockedFeatureTile`, `LockedChip`, `showLockedFeatureSheet` — non-V1 features stay VISIBLE (as the reference shows the full vision) but never fake success: group chats, video calls, USSD/bank-transfer funding, 2FA, biometric login, data/storage controls, the 4th (Dash) theme, open marketplace, games. Wired into Settings, Me, Wallet fund sheet, Calls tab, ThemePicker.

**Android voice-to-text capability fixes** (`core/voice_service.dart`) — the reported "android capabilities issues":
1. **Runtime mic permission is now requested** via `permission_handler` BEFORE `initialize()/listen()` — on Android 6+ the recognition service never starts without it; this was the primary breakage (the manifest declared RECORD_AUDIO but nothing ever asked).
2. **Busy-engine guard**: `canListen` is false while a session is in flight; a leftover session is `stop()`ed before a new `listen()` (the Android plugin throws "already active" otherwise).
3. **Locale resolution**: requested BCP-47 tags are checked against the engine's installed locales; exact match → use, language-part match (ha-NG → ha-GH) → use, no match → device default AND the UI says so ("No voice installed — listening in the device default language"). Requesting an unsupported tag previously made `listen()` fail silently.
4. **Honest block reasons**: new `SttBlockReason` (permissionDenied / noSpeechService / busy / unknown) surfaced as plain-language messages in onboarding ("Microphone permission is off — allow it in Settings, or type your name"), chat dictation, and the translator. Never a silent dead mic.
5. `VoiceAvailability` enum kept (tests/screens import it); `ensureReady()` re-renders the translator after checks complete.

**Translator aligned to the "Voice Translator (Market Women)" board** (`translator_screen.dart`): brand header ("Speak · Translate · Connect"), Speak/Type segmented entry, existing offline phrasebook + honest no-translation note + Play/Send-to-chat kept unchanged functionally.

**Wallet fund sheet**: Card (Paystack/Flutterwave) live; Bank Transfer + USSD shown as locked chips (approved art shows them; V1 does not fake them).

**Verification (real SDK at /tmp/flutter)**: `flutter analyze` = **No issues found**; `flutter test` = **51 pass / 0 fail** (+2 skipped by design) — includes the new demo/prod `unreadCount` parity test; `flutter test --dart-define=OPPA_DEMO_MODE=true test/demo_mode_test.dart` = 4/4 (CI runs this exact step before the APK build). Startup/flow widget tests updated to the approved copy (Continue / Verify / Create your profile / You're all set! / Chats·Wallet·Calls·Me). The new resend-countdown exposed a **timer leak (real bug)**: the periodic Stream was never cancelled — fixed with a cancellable `StreamSubscription` in dispose.

**BLOCKED (unchanged, genuine)**: APK build + on-device verification still require Codemagic + a device (no Java/Android SDK/emulator in this sandbox). The `oppa-mobile-demo` workflow is unchanged and will run the same gates locally proven here.

**NEXT EXACT TASK**: re-run the Codemagic `oppa-mobile-demo` workflow on this commit, install, and verify: brand welcome → phone → OTP 000000 → **speak-or-type profile** → You're all set → Home; check **Chats/Wallet/Calls/Me** tabs, the locked rows (2FA, video, USSD…) show the honest "coming later" sheet, and the translator requests mic permission on first Speak. Compare visuals against the two reference boards.

---

2026-09-13 (session 10, **URGENT ANDROID APK STARTUP FAILURE INVESTIGATION**, branch `oppa-mobile-demo`) — **ROOT CAUSE FOUND AND FIXED (code-proven, not a guess): the first APK hung on the loading spinner because `app.dart` constructed `SecureTokenStore()` with NO storage, and `SessionStore.bootstrap()` → `tokens.refreshToken()` → `_require()` threw `StateError("SecureTokenStore is not configured")` — an uncaught async error inside initState()'s fire-and-forget future, so no phase transition ever fired and the UI stayed on `AuthPhase.unknown`'s `CircularProgressIndicator()` forever. This was a STARTUP-CRITICAL bug from the very first commit (`d68969b`, where the class was born with the nullable-storage + throw design), latent because no widget test ever pumped `OppaApp` with the real `SecureTokenStore`.**

**Why it was certain (not a guess)**: every step of the chain is in the code — `SecureTokenStore({FlutterSecureStorage? storage})` leaves `_storage` null when constructed bare; `_require()` throws exactly then; `bootstrap()` had no try/catch and no timeout; `_setPhase` was only reached on success; `app.dart` rendered the spinner for `AuthPhase.unknown` with no exit. A debug APK therefore always hung, independent of demo mode, manifest, Gradle, or plugins.

**What was verified as NOT the cause**: the Codemagic demo build DID include `--dart-define=OPPA_DEMO_MODE=true` (workflow script inspects it step-by-step); manifest permissions (INTERNET present; demo is fully offline anyway); Gradle/Flutter version skew (four CI failures already fixed in session 9, build reached `assembleDebug`); `SharedPreferences.getInstance()` (mocked default resolves instantly; main.dart awaits it before runApp); `WidgetsFlutterBinding.ensureInitialized()` (first statement); DemoBackend initialization (no I/O by construction); ConnectivityService (its `_init` no-ops without the plugin and listens async); OutboundQueue (its `_load()` swallows all storage errors by design).

**Fix (three parts)**:
1. **Correct construction** — `apps/mobile/lib/app.dart`: `SecureTokenStore(storage: const FlutterSecureStorage())` with a comment explaining the regression. This is the one-line root-cause fix.
2. **Fail-closed bootstrap** — `apps/mobile/lib/core/session_store.dart`: new `AuthPhase.bootstrapFailed`; `bootstrap()` now (a) catches ANY error from the secure-token read and moves to a VISIBLE `bootstrapFailed` state with a human-readable `bootstrapError` (never silently authenticates), (b) bounds the read with a `bootstrapTimeout` (default 10s, generous for low-end keystore cold starts) so a hung platform channel also fails visible, (c) deduplicates concurrent callers through a single in-flight completer, (d) emits `debugPrint("OPPA.session: …")` phase diagnostics (start / read-done with present=true|false / failure / phase→X) — visible via `adb logcat -s flutter`, no secrets, tokens, or phone numbers ever logged. `unknown` now exists only for the bounded bootstrap duration.
3. **Visible retry UI** — `app.dart` renders `_BootstrapErrorView` for `bootstrapFailed`: error icon, message, demo/production-specific explanation, Retry button that re-runs `bootstrap()` (idempotent via the in-flight completer).

**Second real product bug found by the new flow tests**: `verifyOtp()` set `AuthPhase.authenticated` immediately, so `OppaApp` swapped to `HomeShell` and the onboarding profile/voice-name step was UNREACHABLE (the `awaitingProfileName` flag existed but nothing honored it — the approved speak-your-name flow could never appear). Fixed: `verifyOtp` sets `_awaitingProfile = true`; `OppaApp.build` gates `authenticated && awaitingProfileName` to AuthGate (profile step) until `completeOnboarding()` (which now clears the flag on success/skip/non-fatal save failure) or `signOut()` (also clears it). A restart with a stored token bypasses the gate correctly (bootstrap never sets it).

**Startup diagnostics added** (task §7): `main.dart` logs binding init/ready, SharedPreferences read/ready (key count only), and runApp with the demo flag; `SessionStore` logs every bootstrap step and phase change. Nothing secret is printed at any point.

**New tests (13; suite now 52 + 4 define-gated)**:
- `test/session_bootstrap_test.dart` (9): fresh install (empty storage) → `signedOut` never stuck; stored refresh token (restart after login) → `authenticated`; secure-storage failure → `bootstrapFailed` visible, NEVER authenticated; hung storage read → `bootstrapFailed` within the timeout (stopwatch-verified bound); retry after `bootstrapFailed` re-runs bootstrap and recovers; concurrent bootstrap callers share one run (single phase event); bootstrap never calls the network; default timeout is 10s; phase-event draining asserted.
- `test/startup_ui_test.dart` (5 widget tests, the direct reproduction of the reported failure): **fresh startup reaches `AuthGate` with "Send code" — NOT `CircularProgressIndicator`**; production default identical (no demo banner without the define); broken secure storage shows error + Retry and tapping Retry with recovered storage lands on AuthGate; restart after login goes straight to the 4-tab Home shell (stored refresh token); **full flow phone entry → demo OTP 000000 (via injected DemoBackend) → profile step → Home shell**.
- `test/demo_mode_test.dart` rewritten: asserts `DemoMode.enabled == bool.fromEnvironment("OPPA_DEMO_MODE")` (OFF by default, ON with the define) plus define-gated tests for the 000000 constant — run the enabled variant with `flutter test --dart-define=OPPA_DEMO_MODE=true test/demo_mode_test.dart`; Codemagic now runs it as its own "Verify demo define reaches compiled code" step before the APK build.
- `OppaApp` gained a constructor-only test seam `apiForTesting` (never passed by main.dart; compile-time demo/production selection untouched).

**Verification (all executed with the real SDK at /tmp/flutter)**: `flutter analyze` = No issues found; `flutter test` = **52 pass / 0 fail** (38 previous incl. session-9 demo tests + 14 new) plus the define-enabled demo-mode run = 4/4 pass; `flutter test test/startup_ui_test.dart` proves AuthGate-not-spinner at the widget level. **APK build + device launch remain BLOCKED in this sandbox** — no Java, no Android SDK, no emulator (verified: `which java` → not found, `ANDROID_HOME` empty). The APK must be built by Codemagic (`oppa-mobile-demo` workflow, unchanged build command: `cd apps/mobile && flutter build apk --debug --dart-define=OPPA_DEMO_MODE=true`). On-device logcat capture (task §5, §20) is therefore UNTESTED here; the debugPrint diagnostics above are the capture hooks (`adb logcat -s flutter` should show OPPA.main: → OPPA.session: lines ending in `phase → signedOut`). Item §22 (inspect the uploaded first APK's config) was answered from the recorded CI runs: it was built from `886c751` with the correct demo define — the hang was the app-level StateError above, not a build-config problem.

**Remaining blockers (honest)**: (1) rebuild the APK on Codemagic from this commit and install on a device — completion condition (launch past spinner → AuthGate → demo flow → logout → AuthGate) is expected to pass but requires a real Android runtime; (2) logcat capture on device; (3) restart-after-login and fresh-install checks on the physical device (both covered by widget tests here, which is strong but not device evidence).

**NEXT EXACT TASK**: (1) re-run the Codemagic `oppa-mobile-demo` workflow on this commit; (2) install the APK and verify: launch → AuthGate (logcat shows `OPPA.session: phase → AuthPhase.signedOut`), demo phone → 000000 → profile → Home, kill/restart → Home, logout → AuthGate, and the DEMO BUILD banner visible; (3) only after that device pass, merge `oppa-mobile-demo` → `main` per owner policy. If anything still fails on device, the logcat OPPA.session lines will show the exact phase where it stops.

---

## PREVIOUS SESSION
2026-09-12 (session 9, **DEMO MOBILE BUILD + CODEMAGIC FIRST APK TASK**, branch `oppa-mobile-demo` off `2b8b7d2`) — **Safe demo mode implemented and wired end-to-end; production auth untouched. SDK VERIFICATION EXECUTED: `flutter analyze` = No issues found, `flutter test` = 38/38 PASS (Flutter SDK found at `/tmp/flutter` in a later pass; compile errors found by the analyzer were fixed — see below).**

**Architecture (DI, one injection point)**: new `apps/mobile/lib/core/api_client_base.dart` defines the `ApiClientBase` transport contract (get/post/patch/put/delete returning `ApiResponse`). The real `ApiClient` implements it unchanged; **all** dependents (`SessionStore`, `OutboundQueue`, all 8 repositories) now depend on the interface, not the concrete class. `app.dart` picks `DemoBackend` when `DemoMode.enabled`, else the real HTTP client — no other screen/service changed.

**Demo mode (`demo_mode.dart`)**: `OPPA_DEMO_MODE` is a compile-time `bool.fromEnvironment` with `defaultValue: false` — no runtime switch exists; a product (AOT) build compiled with demo mode **refuses to boot** (guard in `app.dart` build()); demo builds draw an amber **DEMO BUILD** banner on every screen via the MaterialApp builder.

**Demo backend (`demo_backend.dart`, ~880 lines)**: in-process implementation of the full repository surface with **zero network I/O** (no http import, no sockets, no production URLs). Fixed during this session (the file was drafted but had routing/compile bugs): duplicate switch cases removed; call lifecycle (start/answer/decline/hangup/signal/events) moved into `post()` where `/conversations/*` paths actually route; `_DemoCall` missing `status`/`createdAt` fields fixed; call start now returns the shape `CallsRepository` expects (`{id, status, kind}`); events honor the real `sinceSeq` query (was reading a nonexistent field); seeded incoming call materializes after answer/decline so it cannot ring twice; **merchant fulfill** (`POST /business/orders/:id/fulfill`, paid→fulfilled, idempotent) and **owner-only staff role change** (`PATCH /business/:id/staff/:userId`, owner immutable, invalid roles rejected) added — both previously missing so merchant flows would 404 in demo; single-transition call rules enforced (double-answer → `CALL_NOT_FOUND`, hangup non-active → `CALL_STATE_INVALID`); demo OTP now references the single `DemoMode.demoOtp` constant. Money is an isolated local ledger with a deterministic third-transfer failure so the honest failure UI is exercised; payments open `https://demo.invalid/…` and settle nothing.

**Auth UX**: OTP step shows the demo code hint only when `DemoMode.enabled`; production verification path unchanged (the demo code is simply a wrong code against the real API — covered by tests).

**Tests**: `test/demo_backend_test.dart` (16 tests: demo-OFF tripwire; request→verify with `DemoMode.demoOtp` succeeds in-process; wrong code → 401; structural tripwire that `DemoBackend` implements `ApiClientBase` but is **not** an `ApiClient`; endpoint-shape parity for profile/conversations/messages/calls/wallet/business/notifications incl. self-order blocker `BUSINESS_ORDER_SELF_INVALID` and invalid call transitions) and `test/demo_mode_test.dart` (3 tests: compile-time OFF default, product-build flag semantics, OTP/banner constants). **RUN AND PASSING**: the Flutter SDK was located at `/tmp/flutter` and the suite executed for real — `flutter analyze` = **No issues found!**, `flutter test` = **38/38 pass** (19 pre-existing + 19 new demo tests). The analyzer caught and this session fixed three real compile errors in the drafted code: `ApiResponse`/`AttemptKind` were used by `api_client_base.dart` and `demo_backend.dart` without an import (would-be circular import) — resolved by moving both types into `api_client_base.dart` and re-exporting from `api_client.dart` (all existing imports still compile); a non-exhaustive `switch` statement over `AttemptKind` in `outbound_queue.dart` (replaced with an exhaustive switch expression); and the const lints on the demo banner. Also fixed: `orElse: () => null` type error in the seeded-call test.

**Codemagic (`codemagic.yaml`, new)**: workflow `oppa-mobile-demo` (debug APK with `--dart-define=OPPA_DEMO_MODE=true`, analyze+test+build, artifact published, no signing needed) and `oppa-mobile-release` (release APK with **no demo defines**, test suite first so the demo-OFF tripwires run). Release signing group intentionally commented until the owner provisions a keystore.

**Android platform (COMMITTED — fixes the first Codemagic failure)**: the first Codemagic run of `oppa-mobile-demo` failed with `PathNotFoundException: android/app/build.gradle` because the branch never committed `apps/mobile/android` and no workflow scaffolded it. Fixed in commit `9e1bed7`: the flutter-generated Android platform is now **committed** (Gradle wrapper + `gradlew` committed explicitly at mode 100755 so fresh CI clones build with the pinned Gradle 8.12; `local.properties`/`.iml` correctly excluded). `AndroidManifest.xml` gained the permissions the app actually uses — `INTERNET`, `RECORD_AUDIO` (speech_to_text voice onboarding) — plus the Android 11+ `<queries>` entry for `android.speech.RecognitionService` so package visibility cannot silently break voice input; `minSdk` pinned to 23 (`flutter_secure_storage` requires API 23+; avoids CI breakage if a future Flutter lowers the default); app label set to "OPPA". Both Codemagic workflows now include a fail-fast "Verify Android platform is committed" step before pub get. A template `test/widget_test.dart` that `flutter create` added was removed (it tests the default counter app and would fail CI). **Flutter analyze/test VERIFIED with the SDK at `/tmp/flutter` (no issues; 38/38 pass). Android build/device testing remains BLOCKED locally** — no Android SDK, no Java in this sandbox; the committed platform is built by Codemagic instead.

**Docs**: `docs/MOBILE_DEMO_BUILD.md` (new: safety invariants, build/install commands, demo coverage table, honest limits); `apps/mobile/README.md` updated (architecture entries for the new core files, demo-mode section, verification table updated with demo status).

**Production-safety review of this diff**: no production route changed; no OTP bypass anywhere in `apps/api`; demo OTP exists only inside `DemoBackend` in-process; no secrets added; `DemoMode.enabled` default false asserted by tests in every build.

**NOT RUN / BLOCKED (environment)**: Codemagic build (needs the repo connected to a Codemagic project + owner account), Android APK build (no Android SDK/Java here) and device UI/UX testing (needs the built APK + a device). None of these were faked.

**NEXT EXACT TASK**: (1) re-run the Codemagic `oppa-mobile-demo` workflow — FOUR Codemagic failures already fixed: (a) missing `android/` platform (commit `9e1bed7`); (b) toolchain skew — Codemagic `flutter: stable` moved ahead of the committed Gradle 8.12 wrapper whose plugin demanded Gradle ≥ 8.14 (also warned about AGP 9+ DSL); fixed by bumping `gradle-wrapper.properties` to Gradle 8.14 AND pinning both workflows to `flutter: 3.35.3` (the exact version the committed platform was scaffolded with — upgrade Flutter and Gradle together going forward); (c) `speech_to_text 6.6.0` compiles the legacy v1 Android embedding (Registrar) whose engine classes were removed in Flutter 3.29+ — CI Kotlin compile of the plugin failed on 3.35.3; fixed by requiring `speech_to_text: ^7.0.0` (v2 embedding) and migrating `listen()` to `SpeechListenOptions.localeId` (commit `2f8c535`); (d) Gradle daemon OOM — flutter-create default jvmargs (8G heap/4G metaspace) exhausted the CI VM inside the JetifyTransform on the Flutter engine jar; fixed by right-sizing to 4G/1G and `android.enableJetifier=false` (every dependency is AndroidX-native; commit `886c751`). analyze 0 issues + 38/38 tests pass at each fix; (2) install on a device and run the UI/UX acceptance pass; (3) merge `oppa-mobile-demo` → `main` manually after owner review (owner merge policy).

---

Previous: 2026-09-10 (session 8, THIRD-PARTY PROVIDER INTEGRATION — `CODEX_THIRD_PARTY_PROVIDER_INTEGRATION_TASK.md`) — **Real provider layer built and wired** (not just env names): **SMS/OTP failover** — new normalized outcome model (`accepted`/`failed`/`unknown`; unknown NEVER success) in `sms/types.ts`; `BulkSmsProvider` rewritten for **BulkSMS Nigeria API v2** (`POST /api/v2/sms`, Bearer auth, `gateway: "otp"`, `message_id` extraction) and new **Termii adapter** (`POST {TERMII_BASE_URL}/api/sms/send`, `channel: "dnd"` for OTP per Termii docs, account-specific base URL — never hardcoded, `code:"ok"` + `message_id` success); both adapters classify timeout/network as `unknown` (AbortController, endpoint-safe — no blind same-provider retry); **`FailoverSmsGateway`** (configurable primary/fallback via `SMS_PRIMARY_PROVIDER`, per-challenge **durable attempt budget** `SMS_MAX_ATTEMPTS_PER_MINUTE`, every attempt persisted, unconfigured ⇒ fail-closed `SMS_GATEWAY_UNCONFIGURED`); **OtpService** now consumes the normalized gateway: one OTP challenge across provider failover, unknown keeps the challenge verifiable (no burn, no auto-resend), definitive failure consumes it and throws `SMS_DELIVERY_FAILED` (502); auth knows only a normalized SMS port (provider config removed from the auth path). **Durable attempt ledger**: migration `0022_sms_delivery_attempts.sql` (**APPLIED to the live DB** — 22/22 current) with per-challenge time index + provider-message-id index + deny-all RLS + service grants; `PostgresSmsAttemptRepository`. **SMS delivery callbacks**: `POST /v1/sms/webhooks/bulksms` (validated; effects bounded to the DLR ledger — BulkSMS has no HMAC, so no OTP/financial state is reachable) and `POST /v1/sms/webhooks/termii` (HMAC-SHA512 of raw body in `x-termii-signature`, requires `TERMII_WEBHOOK_SECRET`, else 401 fail-closed); append-only terminal-state observations via `SmsDeliveryRecorder`. **Payments hardened to the full task flow** — `PaymentService.handleWebhook` now: raw-body signature verify (Paystack = HMAC-SHA512 of RAW body keyed with the SECRET KEY — no separate webhook secret, per task; Flutterwave = `verif-hash` constant-time) → strict reference shape → **event-type gate** (only `charge.success` / `charge.completed` / `payment.completed` may settle; other signed events acknowledged `ignored` with zero mutation) → server-side provider verify (fail-closed on provider error/timeout) → reference/amount/currency agreement against our recorded intent → ownership from our DB row (userId rides as provider metadata for support only, never trusted) → idempotency (already-paid short-circuit; replay/races credit exactly once) → risk gates → single-transaction settlement (wallet + double-entry ledger reference + audit + outbox). **Honest status model**: Paystack `ongoing`→pending, `abandoned`→abandoned; Flutterwave `pending/processing/new`→pending — pending webhooks are acknowledged with zero mutation (never marked failed), failed/abandoned close the row, and **failed→paid reconciliation** is supported in `markPaidAndCredit` (guarded: fails if a provider_transaction_id was already recorded; `reversed` can never settle); early amount-mismatch check (`PAYMENT_AMOUNT_MISMATCH`) before risk; `PAYMENT_REFERENCE_MISMATCH` 409 when provider resolves a different reference. Adapters take base-URL options (`PAYSTACK_BASE_URL`/`FLUTTERWAVE_BASE_URL` overrides for tests); **Flutterwave stays V3** (encryption key accepted for V3 endpoints that need it, unused by init/verify, never logged). **Config**: `env.ts` rewritten with all canonical names incl. `PAYSTACK_PUBLIC_KEY`, `FLUTTERWAVE_PUBLIC_KEY`, `FLUTTERWAVE_ENCRYPTION_KEY`, `TERMII_*`, `BULKSMS_*`, `SMS_PRIMARY_PROVIDER`, `SMS_SEND_TIMEOUT_MS`, `SMS_MAX_ATTEMPTS_PER_MINUTE`; `describeConfig()` reports **names/presence only** (never values); `GET /v1/config/providers` deployment smoke endpoint; template at `docs/provider-env.example` (root `.env.example` is platform-blocked, so the template lives in docs). **Full provider test suites added**: `sms-gateway.test.ts` (12: accept-stops-chain, failure-fallthrough, timeout-unknown semantics, durable budget, unconfigured fail-closed, throwing adapter contained, BulkSMS/Termii mocked-fetch success/error/ambiguous/timeout classification, Termii dnd-channel assertion), `sms-callback-routes.test.ts` (5: DLR recording/idempotency, malformed rejection, Termii forged/unsigned 401, correct-HMAC acceptance, disabled-flow fail-closed), `payment-providers.test.ts` (8: raw-body HMAC (re-serialized body must fail), status mapping incl. pending/abandoned, kobo passthrough, kobo→major conversion, V3 link shape, verif-hash, non-2xx fail-closed), OTP delivery-semantics tests (unknown keeps challenge, definitive failure consumes, provider message id stored, unconfigured mapping), plus fixed body-parser statuses in `error-handler.ts` (malformed JSON ⇒ 4xx, not 500) and existing webhook route tests updated for the event gate. **Verification (all run)**: API **162 pass / 0 fail / 0 skip with the live DB connected** (was 154+8 skip — the 8 DB-integration tests now pass live too); migration 0022 applied via `scripts/db-run.mjs` (secret never printed); `tsc --noEmit` PASS; flutter analyze 0 issues; flutter test 19/19; secret-leak grep over sms/payments/config clean. **Docs**: `docs/PROVIDER_INTEGRATION.md` (architecture, exact deployed webhook URLs, Render secret checklist, dashboard actions, security gates); `docs/API.md` extended with the real wire contract for the new surfaces — OTP `202 {challengeId, delivery}` shape (submitted/unknown/failed/unconfigured semantics), the two payment webhook routes with their signature schemes and settlement flow, the two SMS delivery-callback routes (BulkSMS unsigned-but-bounded vs Termii HMAC-gated), the `oppa_sms_delivery_attempts` ledger, and `GET /config/providers` (names-only introspection). Helper: `scripts/verify-0022.mjs` (read-only live-DB check of migration 0022's table/indexes/RLS/grants + `otp_challenges.provider_message_id`; run via `node scripts/db-run.mjs node scripts/verify-0022.mjs`; never prints connection material). **BLOCKED (environment, unchanged)**: live provider traffic (no BULKSMS/TERMII/PAYSTACK/FLUTTERWAVE credentials in the sandbox — live verification must run on Render with the owner's keys; see task §11, honestly marked BLOCKED rather than faked); Android build/device (no `android/` platform dir, no Android SDK, no Java); WebRTC media (needs device + TURN); bank payouts (not a V1 backend capability). **Owner actions**: add the 19 Render secrets from task §10, register the 4 webhook URLs in provider dashboards (exact URLs in docs/PROVIDER_INTEGRATION.md), confirm BulkSMS sender-ID approval + Termii DND route + account base URL, keep Paystack/Flutterwave test-vs-live modes aligned.

Previous: 2026-09-09 (session 7, LIVE DATABASE CONNECTED + real schema bugs fixed) — the owner added `DATABASE_URL` and this session connected to the **live Supabase Postgres** for the first time (session/direct pooler port 5432 on the same host; owner rule: never the transaction pooler 6543). **All 21 migrations now APPLIED to the live DB** (0013, 0014–0017, 0018, 0019, 0020, 0021 in this session; value never printed/committed; `.env` is git-ignored and was normalized to a standard `DATABASE_URL=` line). **Real schema bugs found and fixed by executing the previously-skipped tests against live data** (this is what live testing is for):
1. **0019's cross-business FK was impossible** — `(product_id, order_id) → products(id, business_id)` required the ORDER's id to equal the PRODUCT's business_id, so **every legitimate order-item insert was rejected on the live DB**. Fixed by migration `0021_fix_order_item_business_boundary.sql` (order_items gains NOT NULL `business_id`; two correct composite FKs pin item→product and item→order to the SAME business; broken constraint dropped; transactional data pre-check aborts on historical cross-business rows). The **production insert path** in `postgres-business-repository.ts` now sets `business_id` (found broken by the live test, fixed and re-tested).
2. **0013 partial index used `now()`** — "functions in index predicate must be marked IMMUTABLE"; replaced with a plain composite index on `oppa_risk_decisions(user_id, scope)` (a `now()` partial index is semantically wrong anyway; the query filters `expires_at` post-lookup).
3. **`migrate.ts` path bug** — migrations dir resolved to `apps/database/`; now resolves correctly (never surfaced before because every prior run exited on the missing URL).
4. **db-hardening harness bugs fixed** — conversation insert was missing required `created_by`; mid-test failure leaked `bizB` rows and blocked cleanup; the harness re-ran 0019 raw AFTER 0021 (resurrecting the broken FK); now tracks applied files in `schema_migrations` exactly like the production runner and includes 0021.
**Live-DB verification results**: `db-hardening.test.ts` **3/3 PASS against live Postgres** (concurrent one-ringing-call invariant; cross-business item FK rejection + same-business insert OK; RLS enabled on every oppa_ table with zero policies). Focused schema checks: oppa_id citext column + unique partial index on `oppa_profiles` (0020's real target — an earlier check probed the wrong table), duplicate/case-insensitive handle rejected functionally, phone-only profile still valid, calls one-live-per-conversation partial unique index present (predicate stored as `status = ANY(ARRAY[...])`), 0021 composite FKs present, broken 0019 FK absent, deny-all RLS confirmed, 21/21 migrations applied. **Full suite with the DB connected: API 134/134 pass, 0 skip, 0 fail** (previously 126+8 skip); flutter analyze 0 issues; flutter test 19/19; `tsc --noEmit` PASS. Helper scripts committed: `scripts/db-bootstrap.mjs` (locate/normalize URL + gitignore check + migrate, secret never printed) and `scripts/db-run.mjs` (inject DATABASE_URL into any command). **BLOCKED (environment, unchanged)**: Android build/device testing (no `android/` platform dir in repo, no Android SDK, no Java in sandbox); OTP delivery (no SMS provider credential); WebRTC media verification (needs real device + TURN); bank payouts (not a V1 backend capability — wallet settlement is). Web trust surface exists at `web/index.html`. Previous session 6 (OPPA ID + workspace architecture) — implemented from the updated `CODEX_V1_RELEASE_CANDIDATE_TASK.md`. **Backend — OPPA ID**: migration `0020_oppa_id.sql` (citext unique handle, 3–32 chars, `^[a-z][a-z0-9_]*$` starting with a letter, reserved product/system names unclaimable, nullable — phone-only identity stays valid, change rate-limit table + audit event); `ProfileRepository`/`PostgresProfileRepository` + profile routes `GET /profile/oppa-id/available/:id` (never reveals who holds a taken id), `POST /profile/oppa-id` (auth, server-side validation, per-instance rate limit → `OPPA_ID_RATE_LIMITED` 429), `GET /profile/oppa-id/lookup/:id` (minimal public identity only); 4 new adversarial route tests (`profile-oppa-id.test.ts`). **⚠ Migration 0020 NOT APPLIED to the live DB** — `DATABASE_URL` still absent in this sandbox (same blocker as session 3); the owner must run `bun run migrate` where the DB is reachable. **Mobile**: workspace architecture — Business is NO LONGER a consumer tab; personal shell is Home / Chats / Wallet / Me with a workspace switcher (Home app-bar + Me screen) listing Personal + all the user's businesses; switching opens the separate BusinessApp full-screen and never logs out; `ProfileRepository.oppaIdAvailable/setOppaId/findByOppaId`; Me screen OPPA ID editor (live availability check, honest error surface); Connect accepts `@handle` or bare handle and resolves it via lookup before adding (also still accepts phone/user id); **voice-assisted business onboarding** (`_BusinessNameDialog`): Type/Speak segmented control, tap-to-talk, partial+final transcription, TTS read-back, editable confirmation — mirrors the consumer name flow. Verification: flutter analyze 0 issues; flutter test 19/19 PASS; API 126 pass / 8 skip (DB-integration, need DATABASE_URL) / 0 fail; `tsc --noEmit` PASS. Previous: **Business app built as its own surface** (owner instruction: not the consumer UI with merchant buttons added). `apps/mobile/lib/ui/screens/business_app.dart` (~1470 lines): own NavigationBar (Dashboard / Orders / Products / More), dashboard with revenue hero + metrics + quick actions + recent orders (real `GET /business/:id/analytics` + orders list; customer count derived from real orders), products management (add via dialog → `POST /business/:id/products` with naira→minor conversion; server validates), orders with status filter chips (All/Unpaid/To fulfill/Fulfilled/Cancelled), explicit confirm dialog → fulfill (`POST /business/orders/:id/fulfill`), merchant order details with per-state explanations (merchants never cancel customer orders — server-enforced, stated in UI), **Staff & Roles** (roster + owner-only role change), **Customers** (derived from real orders, spend per customer), **Analytics** (ordersTotal/ordersPaid/revenueMinor with honest revenue definition), **Money & payouts** (instant wallet settlement is real; bank payouts honestly marked "not available yet" — no fake payout success), consumer Business tab now launches the Business app via "Open Business app". **Backend additions** (verified, not just written): `GET /business/:id/staff` (staff-roster, membership-gated, phones masked `+23480****678`) and `PATCH /business/:id/staff/:userId` (owner-only via `for update` row locks inside a transaction, owner row immutable, self-change blocked, audit event `business.staff_role_changed`); +2 route-level adversarial tests (roster masking/denial; owner-only role validation incl. `owner` role value rejected and ghost target 404). **Voice onboarding finalized**: speak → transcription now **editable in place** (enabled field, helper "Is this right? Tap to correct it", clear button) → confirm/skip button label reflects state — matches approved UI flow. Old inline merchant screens removed from `me_screens.dart`. Verification: flutter analyze 0 issues; flutter test 19/19 PASS; API 122 pass / 8 skip (DB-integration, need DATABASE_URL) / 0 fail; `tsc --noEmit` PASS.

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
