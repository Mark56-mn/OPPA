# OPPA — ONE-SESSION V1 RELEASE CANDIDATE + PERSONAL/BUSINESS WORKSPACE + VOICE UX

## Mission

Complete, integrate, verify, and release-candidate the OPPA V1 application using the supplied OPPA UI reference images as the **visual source of truth**, the repository as the **implementation source of truth**, and the live API/database as the **runtime source of truth**.

Do not stop after implementing screens. Continue through backend integration, database verification, security, offline/reconnect, voice/translation, real-device verification, visual QA, and final end-to-end acceptance.

If a feature cannot genuinely be tested because of an external/environmental blocker, mark it **BLOCKED**, never PASS, document the exact blocker, and continue with everything else that can be completed.

---

## 0. NON-NEGOTIABLE PRODUCT MODEL — ONE OPPA IDENTITY, PERSONAL + BUSINESS WORKSPACES

OPPA must **not** require a user to choose between a permanent Personal account and a separate Business account during initial phone registration.

The required model is:

> **One OPPA login/identity → one Personal profile → zero or more Business profiles/workspaces → seamless switching.**

### Personal account

A user first creates the normal OPPA identity:

- phone number / verified identity
- personal name and OPPA ID
- profile photo
- personal chats and contacts
- personal calls
- personal wallet
- personal security/session controls

Initial onboarding remains simple and should not force a business decision before the user has completed their personal OPPA setup.

### Business workspace

After personal onboarding, the user can:

- create a Business Profile/workspace
- do this from onboarding after the personal account is ready, or later from Me/Business
- create and manage more than one business if the backend supports it
- belong to businesses as Owner, Manager, Staff or other server-defined roles
- switch between Personal and Business without logging out

A business workspace is **not a second independent OPPA login**.

### Separation requirements

Personal and business data, permissions, navigation and financial boundaries must remain separate.

A business staff member must never gain access to the owner's personal wallet, personal chats, personal profile controls, or personal security data merely because they belong to the business.

Business financial records must not be treated as the user's personal wallet.

### Workspace switcher

Implement a clear, accessible account/workspace switcher, for example:

- Personal: `Your Name — Personal`
- Business: `Business Name — Owner/Manager/Staff`
- `+ Create a Business`

Switching workspace must update the visible navigation and active context immediately and safely.

Notifications/deep links must open the correct workspace/context.

Do not rely on logout/login to change workspace.

### Consumer navigation

The supplied consumer OPPA UI is the source of truth for the personal experience. Preserve the intended OPPA themes and visual language while making the actual navigation functional.

Typical personal navigation includes:

- Chats
- Wallet
- Calls
- Me

Use the actual repository/backend capabilities rather than inventing endpoints.

### Business navigation

Business is a **distinct application experience inside the same OPPA identity**, not the personal UI with a few merchant buttons added.

The Business workspace should have its own information architecture appropriate to the supplied/reference business design and the backend capabilities, including where applicable:

- Business Dashboard/Home
- Orders
- Products/catalogue
- Customers
- Business Messages/inbox
- Staff/team and roles
- Business Wallet / payments / settlement
- Business profile/settings
- Order fulfillment/cancellation
- Support/reporting
- relevant business notifications

Keep the OPPA brand/design system consistent, but do not merge personal and merchant navigation into one confusing screen.

Server-side authorization remains authoritative for every business role and financial action.

---

## 1. UI REFERENCE IMPLEMENTATION

The user has supplied OPPA UI reference images to the agent.

Treat those images as the visual source of truth for:

- onboarding
- OPPA Pulse branding
- Personal OPPA home/chat/wallet/calls/me experience
- theme selection
- typography hierarchy
- spacing
- cards
- buttons
- icons
- bottom navigation
- empty/loading/error/offline states
- confirmation screens
- overall visual polish

Do not replace the supplied design with generic Flutter starter UI.

Implement the missing screens and states so the real application matches the supplied designs as closely as practical while preserving accessibility and platform conventions.

The existing repository already contains Flutter screens, themes, repositories and API integration. Inspect and reuse them before creating duplicate architecture.

---

## 2. ONBOARDING + VOICE-FIRST NAME ENTRY

Onboarding must support both typing and speech.

Required flow:

1. Welcome
2. Phone number
3. OTP verification
4. Create profile
5. Choose OPPA ID
6. Choose OPPA Look/theme
7. Completion
8. Optional Business creation after personal onboarding

### Speak your name

On the profile name field, provide a prominent microphone action:

> **Speak your name**

The user may:

- tap microphone
- speak their name naturally
- receive speech-to-text transcription into the name field
- edit the result
- speak again
- hear/read the detected name back for confirmation
- confirm and continue

This is a core accessibility/Africa-first feature, especially for users who may have difficulty spelling or typing their names.

Do not require English speech if a genuinely supported local language can be used.

Never claim language support that the actual speech/translation provider does not support.

If speech recognition is unavailable offline, provide an honest fallback to typing and/or clearly supported offline capability.

Do not store raw audio unnecessarily.

---

## 3. VOICE-TO-TEXT + TRANSLATION

Build the voice communication feature as a first-class OPPA capability, not a decorative microphone.

Required UX where supported:

- tap/hold to speak
- speech → text
- translate text
- show original + translation
- play translated text aloud
- retry recording
- edit transcription
- send translated text into chat
- use inside Business/customer conversations where appropriate
- clear language selection
- honest unsupported-language/error states
- low-data/poor-network handling

The design must be simple enough for market women and users with limited typing/literacy.

Potential supported languages may include English, Nigerian Pidgin, Hausa, Yoruba and Igbo **only where the selected provider/implementation actually supports them**.

Do not invent a translation backend. Inspect the existing API/provider architecture first. If production provider integration is not available, implement the correct UI/contracts and mark live translation as BLOCKED rather than fabricating success.

Voice messages and voice-to-text must respect privacy/security requirements.

---

## 4. PERSONAL ↔ BUSINESS UX

Implement and test these scenarios:

### New personal user

Phone → OTP → speak/type name → OPPA ID → theme → Personal home.

No business requirement during initial registration.

### Personal user later creates a business

Personal → Me/Business → Create Business → business onboarding → Business workspace.

### Business owner switching

Personal → workspace switcher → Business → merchant dashboard → switch back to Personal without logout.

### Staff member

Staff's own OPPA identity → workspace switcher → assigned Business → only role-authorized business features.

### Multiple businesses

If supported by the backend, one OPPA identity can switch between Business A and Business B. Never leak data between workspaces.

### Notifications

A personal notification opens Personal context.
A business notification opens the correct Business context.

### Financial separation

Personal wallet and Business settlement/payment data must remain logically and visually distinct.

---

## 5. COMPLETE CONSUMER JOURNEY

Prove as much of the following as the environment permits:

Install → launch → onboarding → phone → OTP → profile → voice name entry → OPPA ID → theme → home → contacts/connect → conversation → message → receipt/read state → notification → wallet → payment/funding → transaction/history → security/session → support → logout/revocation → restart/recovery.

Verify loading, empty, error, offline and reconnect states for every important screen.

---

## 6. COMPLETE MERCHANT JOURNEY

Prove:

Personal account → Create Business → business profile → products → staff/roles → customer → order → payment → fulfillment/cancellation → business transaction/settlement → history → support/admin.

Verify that business permissions are enforced by the API and not merely hidden in Flutter.

Verify that switching back to Personal does not expose business-only data and switching into Business does not expose personal-only data.

---

## 7. CHAT + VOICE COMMUNICATION

Verify:

- direct chats
- message sending
- pending/offline messages
- receipts
- reconnect convergence
- duplicate prevention
- voice-to-text
- translation
- voice playback where supported
- voice messages where implemented
- business/customer messaging separation
- reporting/blocking/support

Calls must be treated honestly:

- signaling/lifecycle is not equivalent to real audio/video
- offer/answer/ICE must be genuinely wired if claiming full WebRTC
- permissions must be handled
- network degradation/reconnect must be tested
- TURN requirements must be documented
- no fake connected/media state

---

## 8. WALLET + PAYMENTS

Verify:

- balance display
- history
- funding flow
- payment initialization
- provider redirect/authorization
- webhook verification
- idempotency
- risk checks
- wallet transaction integrity
- reversal/error states
- pending/unknown outcomes
- no false financial success
- no client-controlled balance
- no money operation through the offline queue

Personal and business money must remain separated according to backend contracts.

---

## 9. OFFLINE / AFRICA-FIRST BEHAVIOUR

Test:

- no network
- loss of network during message send
- network restoration
- repeated reconnect
- slow network
- duplicate retry
- app restart with pending queue
- low-data operation
- interrupted media transfer
- interrupted financial request

Requirements:

- no message loss
- no duplicate sends from retry races
- queue is lossless
- financial operations are not blindly retried
- pending/unknown financial states are honest
- reconnect does not hammer the API
- cached screens remain clearly identified as cached/stale when appropriate
- battery/memory use is reasonable

---

## 10. DATABASE + BACKEND VERIFICATION

Inspect the actual live database and repository migrations.

Do not assume a migration was applied because a file exists.

Verify:

- current schema/migration state
- calls tables/invariants
- one active/ringing call constraint per conversation where required
- business/order/product integrity including cross-business prevention
- grants/default privileges
- RLS state/policies
- indexes/constraints
- idempotency constraints
- audit/security tables
- no unintended public access

If `DATABASE_URL` is available, run the real Postgres regression tests. If unavailable, record BLOCKED and continue with repository-side verification.

Never expose or commit database credentials.

---

## 11. SECURITY / ADVERSARIAL ACCEPTANCE

Act as:

- anonymous attacker
- normal user
- revoked device
- malicious client
- replay attacker
- concurrent requester
- business owner
- business manager
- business staff
- customer
- admin

Test at minimum:

- IDOR/BOLA
- cross-user access
- cross-business access
- role escalation
- revoked-session access
- replay/idempotency
- concurrent financial requests
- malformed payloads
- oversized input
- rate limits
- OTP abuse
- report abuse
- payment/webhook spoofing
- client-controlled balance/role/identity
- sensitive logs
- secrets in source/build artifacts
- debug backdoors
- mock success paths
- provider-secret leakage

Fix discovered vulnerabilities rather than merely documenting them when they are within repository scope.

---

## 12. ANDROID / REAL DEVICE VERIFICATION

If an Android/Flutter environment is available, actually:

- build the APK/AAB
- install/run on an emulator or real device
- navigate through onboarding
- test microphone permission
- test voice name entry
- test translation UI
- test personal/business workspace switching
- test chat
- test wallet/payment UI
- test notifications
- test call permissions/lifecycle
- test offline/reconnect
- test logout/revocation
- restart the application and verify recovery

Do not mark these PASS if only source inspection was performed.

If Android/Flutter tooling is unavailable, mark each affected check BLOCKED and record the exact environment limitation.

---

## 13. VISUAL QA

Compare implemented screens against the supplied reference images.

Check:

- dimensions/responsiveness
- spacing
- typography
- theme colors
- cards
- buttons
- navigation
- icon placement
- profile/avatar treatment
- onboarding progression
- OPPA Pulse branding
- Fluid Africa / Everyday OPPA themes
- dark/light presentation where applicable
- Business workspace visual distinction
- accessibility/tap targets
- loading/error/offline states

Do not claim pixel-perfect verification without actually viewing the running application.

---

## 14. RELEASE SAFETY CHECK

Before declaring V1 release candidate:

- no secrets in repository
- no provider secrets in Flutter
- no hard-coded OTP bypass
- no universal/master OTP
- no debug authentication bypass
- no mock production success
- no fake payment success
- no client-controlled wallet balance
- no client-controlled role/identity
- no unsafe retry of financial operations
- no accidental public database access
- no unintended WhatsApp V1 feature expansion
- no Browser/VPN/Mini Apps expansion
- no unnecessary dependencies
- no high/critical unresolved security defect
- Business and Personal data boundaries verified
- voice/translation claims match actual provider capability

---

## 15. VERIFICATION COMMANDS

Run the strongest available verification set, including as applicable:

- Flutter dependency resolution
- `flutter analyze`
- `flutter test`
- Android debug/release build
- API typecheck
- API build
- API tests
- DB migration/integration tests
- security/adversarial tests
- static scans
- dependency/security scans
- API smoke tests
- real-device/E2E tests

Record exact commands and results.

---

## 16. COMPLETION RULE

You are **NOT DONE** merely because:

- the UI compiles
- screens exist
- the API tests pass
- a handoff says complete
- a migration file exists

V1 is complete only when the implemented product is integrated and the strongest available end-to-end evidence supports:

1. backend/database verified
2. security/adversarial checks completed
3. consumer journey works
4. merchant/business journey works
5. Personal/Business workspace boundaries work
6. offline/reconnect behaviour works
7. Flutter is genuinely connected to the API
8. supplied UI is implemented and visually checked where tooling permits
9. voice name entry is implemented or honestly BLOCKED
10. voice-to-text/translation is implemented or honestly BLOCKED
11. Android verification is completed or honestly BLOCKED
12. calls are honestly scoped and verified
13. no critical/high unresolved security defect remains
14. every blocked check is documented
15. `CODEX_HANDOFF.md` contains the final exact state

Do not stop after the first successful stage. Continue until genuine V1 completion or a real external/environmental blocker prevents further progress.

---

## 17. CREDIT / CONTEXT EXHAUSTION

If credits, context or execution time are exhausted:

Update `CODEX_HANDOFF.md` before stopping with:

- starting commit
- ending commit
- completed stages
- partially completed stages
- untouched stages
- exact files changed
- exact migrations applied/not applied
- exact database verification status
- exact Flutter verification status
- exact Android verification status
- exact UI/reference verification status
- voice name entry status
- translation status
- Personal/Business workspace status
- calls/WebRTC status
- tests run and results
- security findings
- known blockers
- risks
- exact next action

Never fabricate completion or test results.

---

## Final instruction

**Execute this task, do not merely explain it. Inspect first, implement second, integrate third, test fourth, attack fifth, visually verify sixth, and only then report the final state.**

The user's supplied UI images are the design reference. The repository/API/database are the technical truth. The final product must provide one OPPA identity with cleanly separated Personal and Business workspaces, seamless switching, Africa-first voice assistance, and a genuinely verified end-to-end application.
