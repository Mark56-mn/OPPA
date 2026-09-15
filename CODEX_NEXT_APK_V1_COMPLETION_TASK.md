# OPPA — NEXT APK V1 COMPLETION + ZERO-KNOWN-UI-BUG TASK

**Target branch:** `oppa-mobile-demo`
**Baseline at task creation:** `74cadf00ffb955c4bcc1b6c24a7ab59b0d4226a8`
**Purpose:** produce the next installable OPPA APK only after the current V1 mobile experience has been audited, corrected, integrated and verified.

## 0. NON-NEGOTIABLE MISSION

The next APK is not another UI experiment.

It must be the next **release-candidate-quality V1 mobile build** from the actual repository state, fixing known problems across:

- UI/UX
- branding/icon/splash
- onboarding
- navigation
- notifications
- messaging
- translator/voice
- calls
- wallet/payments
- business workspace
- security/settings/support
- offline/reconnect
- feature visibility and honest locked states
- Android runtime behavior
- demo-mode testing
- production parity
- backend/API integration gaps that affect the mobile experience

Do not stop after visual work. Do not stop after tests pass. Continue through the complete acceptance path until genuinely complete or blocked by a real external/environment limitation.

Read before starting:

1. `OPPA_MASTER_BUILD_SPEC.md`
2. `CODEX_AUTOPILOT.md`
3. `CODEX_SPEED_PROTOCOL.md`
4. `CODEX_BUILD_MAP.md`
5. `OPPA_UI_UX_MASTER_DNA.md`
6. `CODEX_V1_RELEASE_CANDIDATE_TASK.md`
7. `CODEX_HANDOFF.md`
8. this file

The repository is the implementation source of truth. The approved UI reference images supplied by the owner are the visual source of truth. Live API/database state is the runtime source of truth.

---

# 1. IMPORTANT CURRENT-APK FINDING

The owner supplied a new `app-debug.apk` for inspection.

Actual APK inspection found:

- valid Flutter APK structure;
- approximately 150 MB;
- Android manifest present;
- Flutter assets present;
- launcher resources present under `mipmap-*`;
- the launcher image is still the **default Flutter icon**, not the approved OPPA Pulse icon.

Therefore the supplied APK must **not** be treated as proof that the latest UI/branding commit is what the device is running.

The current GitHub branch has newer UI work than that APK. The next APK must be rebuilt from the latest intended branch commit after all fixes, and the final artifact itself must be inspected.

### APK artifact acceptance

Before calling the APK complete:

- verify package/application label;
- verify package ID;
- verify launcher icon resources are OPPA branding, not Flutter;
- verify OPPA Pulse launch/splash presentation;
- verify no demo-only configuration accidentally exists in a production release build;
- verify build number/version;
- verify APK was built from the expected commit;
- verify debug demo APK and production release APK are not confused;
- install and launch on a real Android device when available.

Flutter's Android deployment guidance requires launcher resources to be replaced under `android/app/src/main/res` and the application manifest to reference the intended icon; the launch screen is separately controlled by Android launch-screen resources. Follow those platform rules rather than relying only on Flutter widgets.

---

# 2. VISUAL SOURCE OF TRUTH — OWNER APPROVED UI

The owner supplied four visual reference boards in the current task conversation. Treat them as the approved OPPA UI direction.

They establish:

## Brand

- OPPA Pulse orb/sphere is the official brand mark.
- OPPA wordmark is white in the dark Pulse presentation.
- `PULSE` is violet/purple.
- Dark OPPA Pulse is the default/futuristic look.
- The orb has blue/violet/magenta/amber light trails.
- The mark must appear consistently in onboarding, splash, brand surfaces and launcher treatment.

## Approved themes

1. **OPPA Pulse** — dark, futuristic, violet/purple, energetic.
2. **Fluid Africa** — warm amber/orange, expressive, African-inspired.
3. **Everyday OPPA** — clean, practical, green/light.

Theme switching changes presentation only. It must never alter account, chat, wallet, permissions, security or business data.

## Onboarding reference

The approved journey is approximately:

1. Welcome to OPPA
2. Enter phone number
3. Verify number / OTP
4. Create profile
5. Speak/type name where supported
6. Profile image
7. OPPA ID
8. Choose OPPA Look
9. Security/permissions where required
10. You're all set
11. Start OPPA

The experience must not get stuck on a spinner, silently fail, skip required steps or jump to Home before onboarding is actually complete.

## Personal navigation reference

The personal shell is:

**Chats · Wallet · Calls · Me**

Business is a workspace, not a permanent fifth personal tab.

## Personal screens to complete/audit

- Chats/Home
- search
- All/Unread/Groups/Businesses filters
- Contacts/Connect
- contact profile
- new chat
- chat thread
- message composer
- voice message where supported
- message translation
- message read/delivery details
- call history
- incoming/outgoing voice call
- video call UI with honest capability state
- Wallet
- Fund Wallet
- Send money
- Receive/Request where supported
- payment checkout
- payment result states
- transactions
- Notifications
- My Profile/Me
- Settings
- Appearance
- Security
- Devices/Sessions
- Privacy
- Help & Support
- Report/Block
- Offline/Reconnect

## Business screens to complete/audit

Business is a separate full-screen workspace using the same OPPA design system:

- business dashboard
- products
- add/edit product
- orders
- order detail
- fulfillment
- customers
- customer detail
- merchant chat
- business profile
- staff/roles
- analytics
- payments/settlement state
- business settings

Switching Personal ↔ Business must not require logout and must not leak data across workspaces.

## Voice Translator

Reference is a practical African/market communication tool:

- Speak/Type
- choose source language
- choose target language
- listening state
- translation result
- playback
- send to chat
- clear unsupported/error state
- microphone permission handling

Do not pretend offline phrase lookup is general machine translation. If the production translation provider is not connected, show an honest unavailable state.

## Offline/low-data reference

The UI explicitly includes:

- You're offline
- Retry
- low-data mode
- image/video download controls
- clear queued/pending state

Never show an offline financial transfer as completed.

---

# 3. CURRENT IMPLEMENTATION MUST BE AUDITED, NOT RECREATED

The latest branch already contains substantial work, including:

- vector OPPA Pulse brand kit;
- three theme tokens;
- rebuilt onboarding;
- personal Chats/Wallet/Calls/Me navigation;
- workspace switcher;
- Business app;
- locked-feature system;
- voice capability fixes;
- translator;
- notifications/settings foundations;
- demo backend;
- startup failure handling;
- provider/backend integrations.

Inspect these implementations before changing them.

Do not replace working architecture merely to make a screenshot look different.

Fix the root cause when something is broken.

---

# 4. MASTER GAP AUDIT

Create an internal matrix for every feature/screen:

- implemented and verified
- implemented but visually wrong
- implemented but functionally incomplete
- implemented but not reachable
- implemented only in demo mode
- backend exists but mobile is not wired
- mobile exists but backend is missing
- blocked by provider/device/environment
- security-sensitive
- broken

Then work through every actionable gap.

Do not mark a feature complete simply because a Dart class or route exists.

---

# 5. STARTUP / ANDROID RUNTIME

The previous APK spinner problem was traced to `SecureTokenStore` being constructed without platform storage. That root cause has been fixed in source.

Now prove the complete runtime path:

Fresh install:

`launch → splash → welcome/auth gate`

No infinite spinner.

Test:

- first launch
- cold start
- warm start
- app killed/reopened
- stored session restart
- logout
- secure-storage failure
- timeout/failure recovery
- retry

If a runtime problem occurs, capture logcat and fix the actual cause.

No permanent `CircularProgressIndicator` may be the only response to an authentication/bootstrap failure.

---

# 6. BRANDING / ICON / SPLASH

This is mandatory.

Replace any remaining Flutter branding in:

- launcher icon
- adaptive launcher icon where applicable
- Android manifest reference
- splash/launch screen
- app label
- visible brand assets

Use the approved OPPA Pulse orb/wordmark design already implemented in the repository where appropriate.

Do not use the Flutter logo.

Do not create a random new logo.

If the vector OPPA brand painter is used in Flutter UI, ensure the Android launcher has a proper native launcher asset rather than depending on a Flutter widget that cannot appear before Flutter starts.

Add automated/build checks that fail if the default Flutter launcher asset remains.

---

# 7. DESIGN SYSTEM / RESPONSIVENESS

Use the existing `OPPA_UI_UX_MASTER_DNA.md` token architecture.

Verify:

- safe areas
- keyboard-safe layouts
- 44dp minimum interactive targets
- readable text
- dynamic text scaling
- semantic labels
- consistent typography
- consistent spacing
- consistent card/button/input treatment
- loading/disabled/error states
- reduced-motion behavior
- light/dark/theme consistency

Do not scatter one-off hard-coded colors or component variants.

Fix shared components/tokens instead of patching individual screens repeatedly.

---

# 8. ONBOARDING / AUTH

Test the entire journey in demo mode:

`Welcome → phone → OTP 000000 → profile → speak/type → completion → Home`

Verify:

- OTP entry
- resend countdown
- resend cleanup on dispose
- invalid OTP
- expired OTP
- blocked/limited OTP
- profile save
- typed name
- speech name
- editable transcription
- mic permission denial
- unsupported speech service
- OPPA ID availability
- OPPA ID invalid/taken
- theme selection
- completion
- restart after completion

Production must never accept the demo OTP.

---

# 9. MESSAGING / CONTACTS

Verify real repository/API wiring for:

- contact discovery
- OPPA ID lookup
- add/connect
- conversation creation
- chat list
- unread badges
- message send
- pending state
- delivered/read receipts
- failed send
- retry
- duplicate prevention
- offline queue
- reconnect
- message pagination
- search
- report/block

If a UI control exists in the approved reference, it must either work or honestly explain that the capability is unavailable/locked.

No dead buttons.

---

# 10. NOTIFICATIONS — EXPLICITLY CLOSE THIS GAP

Notifications are a required V1 feature.

Verify end-to-end:

`event → persistence/outbox → delivery/in-app representation → unread count → notification screen → mark read → preferences → deep link/context`

Required categories include where supported:

- new message
- payment received
- payment sent/status
- order update
- security alert
- new device/login
- missed call
- support/report update

Verify:

- list loads
- unread badge is correct
- single mark-read works
- mark-all-read works
- refresh preserves state
- duplicate notification events do not duplicate user-visible notifications
- notification opens the correct screen
- Business notification opens the correct Business workspace
- Personal notification does not accidentally open Business context
- offline state is honest
- empty/error/loading states exist
- preferences are persisted

Do not put OTPs, tokens, secrets or unnecessary financial/security data into notification payloads.

---

# 11. CALLS

Verify the current call lifecycle end-to-end.

At minimum:

- call list/history
- outgoing call
- incoming call
- accept
- decline
- hangup
- microphone permission
- state transitions
- failure handling
- retry

If real WebRTC audio/video is not available, the UI must clearly say what is unavailable. Never show fake connected video/audio.

Video may remain a visible locked/coming-later feature only if that matches the actual V1 capability and reference.

---

# 12. VOICE / TRANSLATOR

Verify Android runtime behavior:

- microphone permission request
- permission denied explanation
- speech service unavailable explanation
- locale selection/fallback
- busy engine protection
- start/stop
- retry
- transcription
- translation/phrasebook semantics
- TTS playback
- send-to-chat

No silent microphone failure.

No claim of machine translation where only phrasebook/dictionary functionality exists.

---

# 13. WALLET / PAYMENTS

Audit the UI and backend together.

Required user journey:

`Wallet → Fund/Send → recipient/amount → Review → authorization → processing → server-confirmed result`

Verify:

- balance is server authoritative
- no client-only balance mutation
- integer minor-unit handling
- fees/currency display
- pending state
- success only after server/provider confirmation
- failure state
- abandoned state where applicable
- duplicate payment protection
- payment history
- transaction detail
- Paystack integration
- Flutterwave V3 integration
- webhook verification
- idempotent settlement
- provider verification
- replay protection
- ownership checks

Bank transfer/USSD must remain visibly locked if the current backend does not genuinely support them.

Never fake payout success.

---

# 14. BUSINESS WORKSPACE

Audit the complete Personal → Business transition.

Verify:

- create/select Business
- workspace switcher
- business dashboard
- product creation/editing
- product ownership
- order list
- order detail
- fulfillment
- customer view
- merchant chat
- staff/roles
- analytics
- business payment state
- business settings
- sign out/session behavior

Adversarially verify cross-business isolation.

A merchant must not create an ordinary customer order against its own business unless a future explicitly authorized internal flow exists.

---

# 15. SECURITY / ME / SETTINGS / SUPPORT

Verify every visible settings row.

No dead navigation.

Complete or honestly lock:

- profile editing
- OPPA ID
- appearance/themes
- devices/sessions
- privacy
- security center
- wallet security
- notifications
- account
- help/support
- report issue
- safety/trust

For locked V1 features, show a consistent explanation rather than pretending they work.

---

# 16. OFFLINE / LOW DATA

Test:

- no connection at launch
- connection loss while viewing chats
- send message offline
- reconnect
- duplicate retry
- app restart with queued message
- low-data mode
- cached profile/chat data
- wallet display while offline

Rules:

- messages may queue where designed;
- financial mutations must not be blindly retried;
- cached balances must be clearly identified as cached/last-updated;
- no offline transfer may display as settled.

---

# 17. PROVIDERS / PRODUCTION PARITY

The backend provider layer now covers BulkSMS/Termii OTP failover and Paystack/Flutterwave V3 payment verification/webhooks.

Inspect actual source and verify mobile integration against the real API contract.

If provider credentials are unavailable in the current environment:

- do not fake live success;
- keep demo mode deterministic;
- mark live-provider verification BLOCKED;
- continue all source-level integration/security tests.

Do not put provider secrets into Flutter.

---

# 18. SECURITY ADVERSARIAL PASS

Before final APK, test at least:

- IDOR/BOLA
- cross-user access
- cross-business access
- revoked session
- revoked device
- role escalation
- replay
- duplicate request
- concurrent mutation
- malformed input
- oversized input
- rate limit
- OTP abuse
- payment webhook forgery
- payment reference mismatch
- payment amount/currency mismatch
- client-controlled balance
- client-controlled role
- demo OTP in production
- secret leakage
- sensitive logging

Fix vulnerabilities, do not merely document them.

---

# 19. TESTING REQUIREMENTS

Run what the environment supports.

### Flutter

- `flutter analyze`
- `flutter test`
- demo define test
- startup tests
- onboarding flow tests
- notification tests
- navigation tests
- theme tests
- business workspace tests
- wallet/payment state tests
- offline/reconnect tests

### Backend

- TypeScript compile/typecheck
- API test suite
- provider tests
- security/adversarial tests
- DB integration tests when live DB is available

### Android

Build the demo APK with:

`flutter build apk --debug --dart-define=OPPA_DEMO_MODE=true`

Build the production APK with no demo define.

Where release signing is available, also build the AAB.

---

# 20. DEVICE QA — MANDATORY WHEN DEVICE/CODEMAGIC IS AVAILABLE

Install the new APK and physically traverse:

1. launch
2. onboarding
3. OTP
4. profile
5. microphone permission
6. voice name
7. theme selection
8. completion
9. Chats
10. Contacts
11. Chat Thread
12. Notifications
13. Wallet
14. Payments UI
15. Calls
16. Me
17. Settings
18. Security
19. Support
20. Business workspace
21. workspace switching
22. offline/reconnect
23. app kill/restart
24. logout

Capture screenshots for the major reference screens and compare against the owner's approved boards.

If a real device is not available, mark the device portion BLOCKED rather than claiming PASS.

---

# 21. VISUAL ACCEPTANCE GATE

The next APK is rejected if any of the following remain:

- Flutter launcher icon
- generic Flutter splash
- infinite startup spinner
- onboarding skips/locks
- wrong primary navigation
- Business shown as an incorrect permanent personal tab
- missing notification screen
- dead notification button
- dead Settings/Profile rows
- broken theme switching
- obvious layout overflow
- clipped text
- unread badges not matching data
- controls with no action and no honest locked explanation
- fake payment success
- fake call connection
- silent microphone failure
- fake translation claims
- offline UI that hides queued state
- cross-workspace data leakage

---

# 22. CODING / SECURITY RULES

- Inspect before modifying.
- Preserve newer work.
- Do not rewrite working modules blindly.
- Do not introduce secrets.
- Do not weaken auth/security.
- Do not create fake providers.
- Do not create client-side financial authority.
- Do not add WhatsApp to V1.
- Do not add VPN/Mini Apps/large Browser expansion.
- Do not add unnecessary dependencies.
- Never claim tests/device/provider checks passed unless actually executed.
- Parallelize independent analysis/tests safely; never concurrently write the same file.

---

# 23. CREDIT EXHAUSTION

If Codex runs out of credits/time/context:

1. stop cleanly;
2. preserve coherent changes;
3. run the fastest meaningful verification;
4. commit completed work;
5. update `CODEX_HANDOFF.md`;
6. record exact files and commits;
7. list PASS / PARTIAL / BLOCKED / NOT DONE;
8. record exact test/build results;
9. identify the single highest-priority remaining task.

Do not leave the repository in an ambiguous state.

---

# 24. FINAL HANDOFF FORMAT

`CODEX_HANDOFF.md` must finish with:

### NEXT APK STATUS

- branch:
- commit:
- APK workflow:
- APK artifact:
- APK build number:
- launcher icon verified:
- splash verified:
- startup verified:
- onboarding verified:
- notifications verified:
- messaging verified:
- calls verified:
- wallet verified:
- payments verified:
- business verified:
- security verified:
- offline verified:
- visual reference comparison:
- Flutter analyze:
- Flutter tests:
- API tests:
- typecheck:
- DB tests:
- provider live tests:
- device tests:

Then list:

- PASS
- PARTIAL
- BLOCKED
- NOT DONE
- known risks
- exact next action

---

# 25. DEFINITION OF DONE

The next APK is DONE only when:

1. it is built from the intended current branch/commit;
2. the launcher icon is the actual OPPA icon, not Flutter;
3. the startup spinner problem is gone;
4. onboarding is traversable end-to-end;
5. the approved OPPA Pulse/Fluid Africa/Everyday OPPA visual system is implemented consistently;
6. personal navigation matches the approved design;
7. notifications are real and reachable;
8. messaging states are correct;
9. calls are honest about actual capability;
10. wallet/payment states are server-authoritative;
11. Business is a proper workspace;
12. security/settings/support are reachable and honest;
13. offline/reconnect behavior is safe;
14. no obvious dead buttons/placeholder screens remain in V1 scope;
15. tests/typecheck/builds that are available actually pass;
16. device checks are executed when the environment permits;
17. unavailable external capabilities are explicitly marked BLOCKED;
18. `CODEX_HANDOFF.md` contains exact evidence;
19. no critical security bypass remains;
20. no WhatsApp/V2 scope has been introduced.

**Do not stop after making the UI look good. The objective is the next APK that is visually correct, functionally integrated, secure, honest about unavailable capabilities, and tested as far as the environment permits.**
