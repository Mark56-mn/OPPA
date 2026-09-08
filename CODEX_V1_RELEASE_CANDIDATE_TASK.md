# OPPA — V1 COMPLETION MASTER TASK

## Mission

Complete the OPPA V1 application from the **actual current repository state** to a genuinely integrated, release-candidate state.

The supplied UI reference images are the **visual source of truth**. The repository is the **implementation source of truth**. The live API/database is the **runtime source of truth**.

Do not stop at UI creation, source inspection, unit tests, or a build that merely compiles. Execute the work below in order, verify each completed area, and continue until V1 is genuinely complete or a real external/environmental blocker prevents further progress.

If a capability cannot be tested, mark it **BLOCKED**, never PASS. Record the exact blocker and continue with everything else.

---

# 0 — START HERE: ACTUAL-STATE AUDIT

Before changing architecture or code:

1. Inspect the entire repository tree.
2. Read `OPPA_MASTER_BUILD_SPEC.md`.
3. Read `CODEX_BUILD_MAP.md`.
4. Read `CODEX_HANDOFF.md`.
5. Read all current V1 task/spec files.
6. Inspect the actual Flutter source, API source, migrations, tests and web source.
7. Compare implementation against the supplied UI reference images.
8. Produce an internal gap matrix of:
   - implemented
   - partially implemented
   - missing
   - blocked
   - broken
   - security-sensitive
9. Do not recreate functionality that already exists.
10. Do not trust previous handoff claims without checking the source/tests/database where possible.

Then execute the remaining tasks below.

---

# 1 — PRODUCT ARCHITECTURE: ONE OPPA IDENTITY + PERSONAL/BUSINESS WORKSPACES

This is a **non-negotiable architecture decision**.

## Required model

> One OPPA login/identity → one Personal profile → zero or more Business workspaces → seamless switching.

A user does **not** create a separate Business login during initial phone registration.

### Personal workspace

Must contain the user's:

- name/profile
- OPPA ID
- contacts
- personal chats
- personal calls
- personal wallet
- personal security/session controls
- personal settings

### Business workspace

A user can create a business after personal onboarding or later.

A business can have:

- Owner
- Manager
- Staff
- other server-defined roles

Staff members use their own OPPA identities and are granted access to the business workspace.

## Workspace isolation

Personal and Business data must never be mixed.

A business staff member must not gain access to:

- owner's personal wallet
- personal chats
- personal security controls
- personal profile controls
- personal sessions

Business financial data must be separate from personal wallet data.

## Workspace switcher

Implement a clear switcher showing:

- `Your Name — Personal`
- `Business Name — Owner/Manager/Staff`
- `+ Create a Business`

Switching must happen without logout.

Switching must change the active navigation/context.

Notifications/deep links must open the correct workspace.

If multiple businesses are supported by the backend, support switching among them without cross-business leakage.

## Critical correction to current UI

Do **not** leave Business as simply a permanent fifth tab beside the personal Home/Chats/Wallet/etc.

Refactor the navigation so the personal workspace has its own shell and the Business workspace has its own merchant shell.

The OPPA visual design system remains shared, but the information architecture is different.

---

# 2 — PERSONAL UI COMPLETION FROM SUPPLIED REFERENCES

Implement the supplied personal OPPA UI rather than generic Material starter screens.

Audit and complete:

- Welcome
- onboarding
- Home
- Chats
- Chat Thread
- Contacts/Connect
- Calls
- Wallet
- Me/Profile
- Security
- Notifications
- settings
- support/help
- error/loading/empty/offline states

Preserve the supplied OPPA visual language and existing theme architecture.

Complete responsive layouts, spacing, typography, cards, buttons, icons, avatars, navigation and interaction states.

Do not claim visual completion without actually viewing the running application when tooling permits.

---

# 3 — ONBOARDING COMPLETION

Build the complete onboarding journey:

1. Welcome
2. Phone number
3. OTP
4. Create profile
5. Profile photo/avatar
6. Speak/type name
7. OPPA ID selection
8. OPPA ID availability
9. OPPA Look/theme
10. required permissions
11. completion
12. optional `Create a Business`

The user should reach a usable Personal workspace without being forced to create a Business.

---

# 4 — VOICE-FIRST NAME ENTRY

This is a core Africa-first V1 feature.

The profile name field must support:

- normal typing
- microphone button
- speech-to-text
- edit transcription
- retry
- confirmation
- read-back/TTS where genuinely supported

The experience must be simple enough for users with limited typing/literacy.

Do not claim local-language support unless the actual provider supports it.

If production speech recognition cannot be connected, build the correct UI/provider abstraction and mark live capability BLOCKED rather than fabricating success.

Do not retain raw audio unnecessarily.

---

# 5 — OPPA ID / IDENTITY COMPLETION

The supplied design includes an OPPA ID concept.

Audit the current backend and add the missing server/client functionality required for:

- OPPA ID creation
- availability checking
- uniqueness
- validation
- reserved-name protection
- safe changes where allowed
- display/search by OPPA ID
- profile display

Identity must be server-authoritative.

Do not allow the client to claim an unavailable or another user's ID.

---

# 6 — CONTACTS + CONNECT COMPLETION

Complete the personal connection experience:

- search/discovery supported by existing API
- OPPA ID search
- contact profile
- add/connect
- start chat
- group creation if supported
- group details
- group members
- leave group
- appropriate empty/error/loading states

Use the existing repository/API capabilities before adding new endpoints.

---

# 7 — MESSAGING COMPLETION

Complete:

- conversation list
- chat thread
- message composer
- send state
- pending state
- sent/delivered/read receipts
- failed state
- retry
- offline queue visibility
- reconnect convergence
- duplicate prevention
- message search where supported
- media handling where already supported
- reporting/blocking/support
- group messaging where supported

The UI must never show a financial or message operation as successful when the server has not confirmed it.

---

# 8 — VOICE-TO-TEXT TRANSLATOR

Build the OPPA voice translator as a real first-class feature.

Required UX where supported:

- choose spoken language
- choose target language
- tap/hold microphone
- speech → text
- edit text
- translate
- show original and translated text
- text-to-speech playback where supported
- send translated result into chat
- use in Business/customer conversations
- retry/error states
- unsupported-language state
- poor-network/low-data state

Prioritize African use cases including market women.

Potential languages include English, Nigerian Pidgin, Hausa, Yoruba and Igbo **only if actually supported by the selected production provider**.

Inspect existing provider/API architecture first. Do not invent a fake translation service.

If provider credentials/integration are unavailable, mark live translation BLOCKED while still completing the correct contracts/UI where possible.

---

# 9 — VOICE MESSAGES

Where voice messages are within the current V1 scope/backend capability, complete:

- record
- cancel
- send
- playback
- progress
- retry
- failed state
- permissions
- privacy handling
- network interruption handling

Do not confuse voice messages with speech-to-text translation.

---

# 10 — CALLS / WEBRTC

Current call lifecycle/signaling must not be presented as full audio/video unless media is genuinely implemented.

Complete or explicitly scope:

- call history
- incoming call
- outgoing call
- accept/decline
- microphone permission
- camera permission
- real audio
- real video
- WebRTC offer/answer
- ICE candidates
- connection state
- reconnect
- network degradation
- call end
- failure
- TURN configuration where required

If real media infrastructure is not available, clearly mark full media BLOCKED and do not fake connected/audio/video state.

---

# 11 — WALLET UX COMPLETION

Complete the Personal wallet journey:

- wallet landing
- balance
- transaction list
- transaction detail
- fund wallet
- provider authorization/return
- pending
- success
- failed
- send money
- recipient selection
- amount
- review
- step-up/security confirmation
- processing
- success/failure/pending
- receive/request where supported
- limits/fees
- wallet settings
- help/dispute

The existing secure backend is the authority for balances and transactions.

Never implement client-controlled balance changes.

---

# 12 — PAYMENTS COMPLETION

Verify and complete:

- payment initialization
- provider authorization
- provider verification
- webhook verification
- idempotency
- risk checks
- wallet crediting
- reversals
- pending/unknown outcomes
- provider errors
- payment history
- reconciliation
- refunds where V1 backend supports them

Do not report success based only on a client redirect.

Financial operations must not use the generic offline retry queue.

---

# 13 — BUSINESS PLATFORM COMPLETION

Business must be a distinct workspace inside the same OPPA identity.

Build the complete merchant information architecture:

### Business onboarding

- create business
- business name
- business category
- business profile
- logo/photo
- description
- location/contact information
- voice-assisted business name/details where supported
- completion

### Business dashboard

- business summary
- orders
- sales/payment summary
- alerts
- notifications
- quick actions

### Products

- product list
- product detail
- create product
- edit product
- archive/delete where allowed
- product description
- price
- images where supported
- inventory/stock where supported

### Orders

- order list
- order detail
- order status
- payment state
- fulfillment
- cancellation
- customer information appropriate to authorization

### Customers

- customer list
- customer detail
- customer/order history
- business/customer messaging

### Business messages

- business inbox
- customer conversation
- voice-to-text
- translation
- notifications

### Staff/team

- staff list
- invite/add staff
- role display
- role changes where supported
- remove staff
- permissions

### Business finance

- business payment records
- business ledger/settlement view
- payout/settlement status where backend supports it
- reconciliation

Do not mix business settlement data with the user's personal wallet.

### Business settings

- profile
- staff/roles
- notifications
- security
- support

---

# 14 — BUSINESS BACKEND / DATA INTEGRITY

Audit the existing business backend and add only what is actually required.

Verify:

- business membership
- role authorization
- cross-business isolation
- product ownership
- order ownership
- customer isolation
- business financial separation
- composite business/order/product integrity
- idempotency
- audit logging

Attempt malicious cross-business access as part of adversarial testing.

---

# 15 — NOTIFICATIONS COMPLETION

Complete the actual notification UX.

The notification button must navigate to a real notification screen.

Implement where supported:

- notification list
- unread count
- mark read
- mark all read
- preferences
- notification detail/deep links
- Personal vs Business context
- order/payment/security/call/message notifications
- empty/loading/error states

A Business notification must open the correct Business workspace.

---

# 16 — SECURITY CENTER / DEVICES / SESSIONS

Expose the backend security functionality in the UI.

Build:

- Security Center
- active devices
- active sessions
- device detail
- session detail
- revoke device
- revoke session
- security alerts
- security alert detail
- wallet security
- privacy controls
- account controls

Server authorization must remain authoritative.

---

# 17 — SUPPORT / REPORTING / ABUSE

Complete user-facing support/reporting where backend capability exists:

- report user/message/business
- report status
- support entry point
- help/FAQ
- fraud/security report
- relevant report confirmation
- status/history where supported

Verify admin triage remains secure.

---

# 18 — ADMIN / CONTROL CENTER WEB UI

The existing web surface must not be mistaken for a completed Admin Control Center.

Where V1 scope requires it, build the actual admin interface for the existing admin backend:

- dashboard
- users
- user detail
- devices/sessions/security
- wallet/payment operations
- messaging operations
- fraud/risk
- abuse reports
- support
- staff/RBAC
- audit logs
- emergency controls
- system health

Do not create admin bypasses.

Admin permissions must be server-authoritative.

---

# 19 — WEB / TRUST SURFACE

Keep the existing public/trust surface functional and consistent with the actual product.

Verify:

- features
- trust/safety
- privacy
- support
- legal links where required
- no claims for features that are not actually available

Do not expand V1 into the deferred Browser/VPN/Mini Apps scope.

---

# 20 — OFFLINE-FIRST / AFRICA-FIRST COMPLETION

Verify:

- no network
- poor network
- slow network
- network loss during message send
- network restoration
- repeated reconnect
- app restart with pending work
- low-data behaviour
- interrupted media
- duplicate retry

Requirements:

- lossless message queue
- no duplicate sends from retry races
- endpoint-aware retry
- no blind financial retry
- honest pending/unknown financial state
- reconnect does not hammer API
- cached state is clearly identified where necessary
- reasonable battery/memory behaviour

---

# 21 — DATABASE / MIGRATIONS / LIVE SUPABASE

Do not assume migration files equal live database state.

Verify actual live database state.

Check:

- migration history
- calls tables
- call concurrency invariant
- business/order/product integrity
- RLS
- policies
- grants
- default privileges
- indexes
- primary/foreign keys
- idempotency constraints
- audit/security tables
- notification tables
- no unintended public access

Apply pending migrations through the approved migration process when credentials/environment are legitimately available.

Run real Postgres regression tests when `DATABASE_URL` is available.

Never commit or expose database credentials.

---

# 22 — OTP / PROVIDER INTEGRATION

Verify the real OTP provider integration.

No:

- master OTP
- universal OTP
- debug OTP
- authentication bypass
- fake production success

If BulkSMS/provider credentials are not available, record OTP as BLOCKED and continue the rest of the build.

---

# 23 — SECURITY ADVERSARIAL PASS

Attack the completed product as:

- anonymous user
- normal user
- malicious client
- revoked device
- replay attacker
- concurrent requester
- business owner
- manager
- staff member
- customer
- admin

Test:

- IDOR/BOLA
- cross-user access
- cross-business access
- role escalation
- revoked-session access
- replay
- idempotency
- concurrency
- malformed payloads
- oversized input
- rate limiting
- OTP abuse
- report abuse
- payment/webhook spoofing
- client-controlled balance
- client-controlled role/identity
- sensitive logging
- secret leakage
- debug bypasses
- mock success paths
- provider-secret leakage

Fix repository-scope vulnerabilities rather than merely documenting them.

---

# 24 — ANDROID BUILD + REAL DEVICE QA

If Flutter/Android tooling is available:

1. build APK
2. build AAB where practical
3. install on emulator/real device
4. launch
5. onboarding
6. microphone permission
7. speak name
8. theme
9. personal home
10. workspace switcher
11. create Business
12. merchant UI
13. chat
14. notifications
15. wallet/payment UI
16. calls
17. offline/reconnect
18. logout/revocation
19. app restart/recovery

Only mark PASS when actually tested.

If unavailable, mark BLOCKED with exact environment limitation.

---

# 25 — VISUAL QA AGAINST SUPPLIED IMAGES

After implementation, compare the running application to the supplied UI images.

Check:

- onboarding
- OPPA Pulse branding
- typography
- spacing
- cards
- buttons
- icons
- avatars
- navigation
- theme behaviour
- Personal workspace
- Business workspace
- loading/empty/error/offline states
- accessibility/tap targets

Do not claim pixel-perfect or visual completion from source inspection alone.

---

# 26 — COMPLETE END-TO-END ACCEPTANCE

## Consumer

Install → onboarding → phone → OTP → speak/type name → OPPA ID → theme → Personal home → Connect → chat → receipts → notification → wallet → payment → history → security → support → logout → restart/recovery.

## Merchant

Personal → Create Business → business profile → products → staff/roles → customer → order → payment → fulfillment/cancellation → business financial records/settlement → history → support/admin → switch back to Personal.

## Workspace

Personal → Business → Personal → Business A → Business B where supported.

Attempt to access data from the wrong workspace and verify denial.

## Calls

A invites B → incoming call → accept → real media if implemented → network degradation → reconnect → end → history.

## Offline

No network → create/send message → pending → app restart → network restored → sync → no duplicate → correct final state.

---

# 27 — FINAL RELEASE SAFETY CHECK

Before declaring V1 release candidate:

- no secrets in repository
- no provider secrets in Flutter
- no OTP bypass
- no debug authentication bypass
- no fake payment success
- no client-controlled balance
- no client-controlled role/identity
- no unsafe financial retry
- no unintended public DB access
- no high/critical unresolved security defect
- Personal/Business separation verified
- voice/translation claims match actual capability
- calls honestly scoped
- WhatsApp remains V2
- Browser/VPN/Mini Apps remain outside V1

---

# 28 — REQUIRED VERIFICATION

Run the strongest available set:

- Flutter dependency resolution
- `flutter analyze`
- `flutter test`
- Android build
- API typecheck
- API build
- API tests
- DB migration tests
- real Postgres tests
- security/adversarial tests
- static scans
- dependency/security scans
- API smoke tests
- E2E tests
- real-device tests where available

Record exact commands and results.

---

# 29 — HANDOFF / CREDIT EXHAUSTION

If credits, context, time or environment access run out:

Update `CODEX_HANDOFF.md` before stopping.

Record:

- starting commit
- ending commit
- completed tasks
- partial tasks
- untouched tasks
- exact files changed
- migrations applied/not applied
- live DB status
- Flutter status
- Android status
- UI/reference status
- voice name status
- translation status
- workspace architecture status
- business UI status
- calls/WebRTC status
- tests and results
- security findings
- blockers
- risks
- exact next action

Never fabricate test results or completion.

---

# 30 — COMPLETION RULE

The product is **NOT COMPLETE** merely because:

- screens exist
- Flutter compiles
- tests pass
- the API builds
- a migration file exists
- a previous handoff says complete

V1 is complete only when the strongest available evidence supports:

1. Personal UI is implemented.
2. Business UI is implemented as a distinct workspace.
3. One OPPA identity can safely manage Personal + Business context.
4. Workspace switching works without logout.
5. Onboarding is complete.
6. Voice name entry is implemented or honestly BLOCKED.
7. Voice-to-text/translation is implemented or honestly BLOCKED.
8. OPPA ID functionality is implemented or honestly BLOCKED.
9. Messaging works with offline/reconnect behaviour.
10. Wallet/payment flows are integrated and financially safe.
11. Business/order/customer/staff workflows work.
12. Notifications work with correct workspace context.
13. Security/device/session UI works.
14. Calls are honestly implemented/scoped.
15. Live database is verified where credentials/environment permit.
16. Android is verified where tooling/device permits.
17. Visual QA has been performed where a running app can be viewed.
18. Adversarial security testing is complete.
19. No critical/high unresolved security defect remains.
20. Every external blocker is documented.
21. `CODEX_HANDOFF.md` contains the exact final state.

**Do not stop after the first successful stage. Execute the entire task chain.**

---

## Final command to the agent

**Inspect first. Plan from the actual repository. Fix architecture where required. Implement missing functionality. Integrate it with the real backend. Test it. Attack it. Build Android where possible. Visually compare it to the supplied UI. Continue through every remaining task until genuine V1 completion or a real external blocker prevents further progress. Do not merely report what should be done — do the work.**
