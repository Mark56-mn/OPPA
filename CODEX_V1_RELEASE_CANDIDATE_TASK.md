# OPPA — V1 RELEASE CANDIDATE / REAL-DEVICE ACCEPTANCE TASK

## Purpose

This is the mandatory final completion task for the OPPA V1 application.

The goal is to prove that OPPA is not merely implemented in source code, but works as one connected, polished product across the real backend, database, Flutter Android client, consumer experience, business/merchant experience, and required web/admin/trust surfaces.

**The UI reference images supplied to you in the task conversation are the visual source of truth for the intended OPPA experience.** Use them together with the repository source code. Do not replace the intended UX with generic Flutter screens.

This task is mandatory after the existing V1 stages and final acceptance audit. Do not mark OPPA V1 complete until the implementation, integration, security checks, and verification gates below pass or every genuinely blocked item is explicitly documented.

---

# A. START WITH THE REAL SOURCE CODE

1. Inspect the latest git history, branch, status and current tree.
2. Read `CODEX_HANDOFF.md`, `OPPA_MASTER_BUILD_SPEC.md`, `CODEX_BUILD_MAP.md`, and this task.
3. Inspect the actual current implementation before changing anything.
4. Do not trust previous completion claims without checking the source and running verification.
5. Identify every feature that is claimed to exist but is missing, disconnected, placeholder-only, visually incomplete, or unverified.
6. Preserve existing secure architecture and working API contracts unless a change is required to complete the product correctly.
7. Do not add unnecessary frameworks, abstractions, mock layers, or dead code.

---

# B. UI/UX SOURCE OF TRUTH — IMPORTANT

The provided UI images are part of this task. They show the intended OPPA visual language, onboarding, normal-user application, voice translation, wallet/payments, calls, business/merchant experience, offline states, security/support and other product surfaces.

## B1. General visual requirements

Implement the UI to closely match the supplied references in:

- screen hierarchy;
- navigation;
- spacing and layout;
- typography hierarchy;
- button placement;
- cards and list structures;
- icons and actions;
- dark/light/theme behavior;
- OPPA branding;
- empty/loading/error/offline states;
- accessibility and touch targets;
- Africa-first simplicity;
- low-literacy friendliness.

Use the existing three OPPA themes where appropriate:

- Fluid Africa;
- OPPA Pulse;
- Everyday OPPA.

Do not make every screen a dark neon screen if the supplied reference shows a light or theme-specific surface. The user-selected OPPA look must remain coherent throughout the application.

## B2. NORMAL OPPA APP vs BUSINESS APP — KEEP THEM DISTINCT

The source currently contains consumer functionality such as Home, Connect, Shop, Chats, Wallet, Calls, Me/Security and a `BusinessRepository`, but the mobile source does **not** prove that a complete dedicated merchant/business UI exists. Do not confuse the consumer marketplace/shop experience with the merchant operating experience.

The application must have two clearly differentiated experiences:

### Normal OPPA / Consumer

The normal user experience includes:

- onboarding;
- phone/OTP authentication;
- profile and OPPA ID;
- home;
- contacts/connect;
- chat list;
- chat thread;
- message receipts/details;
- voice-to-text/translation;
- voice/video calls;
- wallet;
- funding/payment;
- consumer marketplace/shop;
- consumer order/payment state;
- notifications;
- profile/me;
- privacy/security/devices/sessions;
- support/safety;
- settings/themes;
- offline/reconnect/low-data states.

### Business / Merchant

The business experience must be a separate, purpose-built UI and navigation model, not the consumer Home screen with a few extra buttons.

It must cover, according to the actual V1 backend contracts:

- business onboarding/selection;
- business dashboard;
- business profile;
- products;
- add/edit product;
- orders;
- order detail;
- order status transitions;
- fulfill/cancel actions;
- customers;
- staff and roles;
- analytics where supported;
- business settings;
- business notifications;
- business wallet/settlement/payout views where supported;
- business support;
- merchant/customer chat;
- voice translation for merchant/customer communication where supported;
- loading/empty/error/offline states;
- business-specific navigation.

A consumer must never accidentally receive merchant-only controls, and a merchant/staff member must only see controls authorized by the backend role.

---

# C. COMPLETE THE REMAINING UI

Build/refine every missing or incomplete screen using the supplied UI references and current API contracts.

## C1. Onboarding

Implement the complete onboarding sequence represented by the supplied references:

- welcome;
- phone number;
- OTP verification;
- create profile;
- profile photo;
- OPPA ID selection;
- OPPA look/theme selection;
- security setup where required;
- completion/success;
- honest loading/error/retry states.

### Voice-assisted name entry is mandatory

Many African users, including market women, may not know how to spell their names comfortably. During profile creation:

- provide a clearly visible microphone action beside/in the name field;
- allow the user to speak their name;
- convert speech to text and place the result into the editable name field;
- allow speak-again/retry;
- allow the user to edit the result;
- provide a clear confirmation before continuing;
- never silently overwrite a user-edited value;
- handle microphone permission denial gracefully;
- handle unsupported/unavailable speech services gracefully.

Do not use fake speech recognition or fake success in production. If the actual provider/device capability is unavailable, implement a clean capability state and document the integration limitation.

---

# D. VOICE-TO-TEXT + TRANSLATION — CORE AFRICA-FIRST FEATURE

This is a first-class OPPA capability, especially for market women and users with limited literacy or limited English proficiency. It must not be treated as an optional decorative screen.

## D1. Required capabilities

Where supported by the real implementation/provider:

- tap/hold to speak;
- speech → text;
- editable transcription;
- language selection;
- translation;
- translated text → speech/listen;
- replay;
- send translated result directly to chat;
- use voice translation in merchant/customer conversations;
- useful voice input in other appropriate forms such as profile/business/product fields;
- clear permission/error/offline states;
- low-data behavior where possible.

The intended initial language direction shown in the supplied UI includes:

- English;
- Hausa;
- Yoruba;
- Igbo;
- Pidgin English;
- French where actually supported;
- additional languages only when genuinely implemented.

Do not claim language support merely because a language appears in a dropdown. A language is supported only when the underlying speech/transcription/translation path works or its limitation is explicitly shown.

## D2. Chat integration

A user should be able to:

1. speak naturally;
2. review/edit transcription;
3. translate if desired;
4. listen to the translation;
5. send the resulting message into the conversation.

The recipient should receive an honest representation of what was sent. Do not create a fake translated message that was never produced by the actual translation path.

## D3. Business integration

Business/customer chat should be able to use the same voice/translation capability where supported. Keep the business presentation distinct from the normal consumer UI.

## D4. Privacy/security

- do not log raw private audio unnecessarily;
- do not expose provider credentials in Flutter;
- do not store audio indefinitely without a product requirement;
- clearly handle microphone permissions;
- protect private content and translation requests;
- never send sensitive data to an unapproved third-party endpoint.

---

# E. COMPLETE APPLICATION EXPERIENCE

The release candidate must include, where implemented by V1 scope:

- backend API;
- database migrations/schema;
- authentication and sessions;
- messaging;
- notifications;
- wallet/payments/risk/security;
- consumer marketplace/shop;
- business/merchant;
- admin/control center;
- OPPA-native calls;
- Flutter Android app;
- required web/trust/support surfaces.

Every UI action that claims to perform a real operation must be connected to the correct backend contract or must display a clearly honest unavailable/blocked state.

---

# F. REAL END-TO-END JOURNEYS

Exercise complete journeys rather than isolated unit tests.

## F1. Consumer

```text
install
→ onboarding
→ choose/use language
→ speak/type name
→ phone
→ OTP
→ profile/photo
→ OPPA ID
→ theme
→ device/session
→ home
→ contacts/connect
→ conversation
→ send message
→ voice-to-text/translation
→ receipt/read state
→ notification
→ wallet
→ payment
→ transaction/history
→ security/session management
→ support
```

## F2. Merchant

```text
business onboarding/selection
→ business profile
→ business dashboard
→ product creation
→ product management
→ staff/roles
→ customer
→ merchant/customer chat
→ voice translation
→ order
→ payment
→ order processing
→ fulfill/cancel
→ settlement/history
→ analytics/settings
→ support/admin visibility
```

## F3. Calls

```text
user A
→ invite user B
→ ringing/incoming
→ accept
→ audio/video
→ network degradation
→ reconnect
→ end call
→ call history/state
```

Every flow must use real API/database state. No mocked success responses.

---

# G. OFFLINE / POOR NETWORK / AFRICA-FIRST ACCEPTANCE

Test under conditions representing real African connectivity constraints:

- no network;
- network loss during message send;
- network restoration;
- repeated reconnects;
- slow network;
- duplicate retry;
- app restart while an operation is pending;
- low-data mode;
- media transfer where applicable;
- interrupted financial request;
- voice/translation unavailable offline;
- reconnect after long offline period.

Verify:

- messages remain visible locally as pending when appropriate;
- retry does not duplicate messages;
- synchronization converges to server truth;
- financial operations never show false success;
- pending/unknown financial states are explicit;
- retries are idempotent;
- the app does not hammer the server during reconnect;
- battery/memory-heavy background loops are avoided;
- offline UI is understandable to low-literacy users;
- voice features clearly explain when network/service availability is required.

Financial mutations must never be silently placed into an unsafe offline queue.

---

# H. REAL-DEVICE ANDROID ACCEPTANCE

If an Android build/device environment is available, build and install the release candidate on a real Android device.

At minimum verify:

- launch/startup;
- onboarding;
- microphone permission;
- voice name entry;
- OTP/auth flow;
- secure session persistence;
- messaging;
- voice-to-text/translation;
- notifications;
- wallet/payment UI states;
- consumer shop/order flow;
- separate business/merchant flow;
- call microphone/camera permissions;
- call lifecycle;
- offline/reconnect states;
- low-data state;
- logout/revocation;
- app restart recovery;
- no crash or broken navigation.

If a real device/build environment is unavailable, mark the relevant checks `BLOCKED` rather than claiming PASS.

---

# I. FINAL ADVERSARIAL ATTACK PASS

After integration, attack the complete system again as:

- anonymous attacker;
- ordinary user attacking another user;
- malicious merchant/staff;
- lower-privileged admin;
- revoked device/session;
- replaying client;
- concurrent attacker;
- malformed/spam client.

Focus on cross-module attacks:

- auth → wallet;
- auth → payments;
- device/session → security proof;
- messaging → notifications;
- business → wallet settlement;
- business role → product/order/customer access;
- admin → emergency controls;
- payment webhook → wallet;
- offline queue → financial mutation;
- calls → authorization/rate limits;
- voice/translation → privacy and provider abuse;
- client UI → server-side authorization.

Any discovered vulnerability must be fixed and the attack rerun.

---

# J. RELEASE SECURITY CHECKS

Confirm that:

- no secrets are committed;
- no provider secret is bundled in Flutter;
- no debug/test backdoors remain;
- no fake/mock production endpoints remain;
- no unsafe admin bypass exists;
- no client-controlled balance/role/identity decision is trusted;
- no sensitive logs expose tokens, signatures, private messages or raw audio;
- no universal/master OTP or OTP bypass exists;
- no accidental WhatsApp V1 functionality has been introduced;
- V1 scope has not expanded into Browser/VPN/Mini Apps;
- business authorization is enforced server-side;
- consumer users cannot invoke merchant-only mutations;
- merchant/staff permissions cannot be escalated through the UI or API;
- translation/speech providers cannot be abused as an unauthenticated proxy.

---

# K. VERIFICATION GATE

Run what the environment supports:

- full tests;
- adversarial tests;
- concurrency tests;
- typecheck;
- build;
- lint/static checks;
- migration/schema checks;
- API smoke tests;
- mobile build/install tests;
- end-to-end consumer journey;
- end-to-end merchant journey;
- calls journey;
- offline/reconnect tests;
- voice name/transcription tests;
- translation tests;
- notification tests;
- permission-denial tests.

Record unavailable checks explicitly.

**Do not equate `build succeeded` with `product works`.**

**Do not equate `tests passed` with `security proven`.**

**Do not equate `files exist` with `features complete`.**

---

# L. UI QUALITY GATE

Before declaring completion, visually inspect the actual Flutter application against the supplied reference images.

Check:

- no placeholder screens where the references show finished screens;
- no generic/default Flutter styling where OPPA styling is expected;
- no clipped/overflowing text;
- no unusably small controls;
- no broken bottom navigation;
- no inconsistent theme transitions;
- no missing loading/empty/error states;
- no dead buttons;
- no navigation loops;
- no consumer/business UI confusion;
- voice controls are discoverable and understandable;
- important actions work with one or two obvious taps;
- screens remain usable on normal Android phone sizes.

If visual comparison cannot be performed because the Android UI cannot be run, record it as `BLOCKED` and do not claim visual PASS.

---

# M. DATABASE / BACKEND REALITY CHECK

The release candidate is not complete until the live database state is verified where the environment permits.

Specifically verify:

- required migrations are applied;
- schema matches repository expectations;
- call concurrency invariant exists;
- business/order/product integrity is enforced;
- RLS/grants/default privileges are appropriately hardened;
- backend tests run against a real PostgreSQL database where possible;
- no migration is merely present in source while absent from the live database.

Never fabricate live database verification.

If `DATABASE_URL` or a safe database environment is unavailable, mark live DB verification `BLOCKED` and document exactly why.

---

# N. FINAL COMPLETION RULE

OPPA V1 may only be reported as complete when:

1. repository implementation matches V1 scope;
2. UI matches the supplied intended product direction;
3. consumer and business experiences are clearly separated;
4. voice-assisted name entry is implemented honestly;
5. voice-to-text/translation is implemented or its exact provider limitations are documented;
6. backend and database are verified;
7. security attacks have been attempted and remediated;
8. real consumer and merchant journeys work;
9. calls work to the verified level of the implementation;
10. offline/reconnect behavior is verified where supported;
11. Flutter is genuinely connected to the backend;
12. Android build/device verification passes where the environment permits;
13. no critical/high unresolved security defect remains;
14. all blocked verification items are explicitly documented;
15. `CODEX_HANDOFF.md` contains the exact final state.

Do not stop after writing UI.

Do not stop after passing unit tests.

Do not stop after the security audit.

Continue through implementation, integration, visual QA, real-device testing and final acceptance until the application is genuinely complete or the environment prevents further progress.

---

# CREDIT / ENVIRONMENT STOP

If the environment runs out of credits, time, context or device/build capability, stop cleanly and update `CODEX_HANDOFF.md` with:

- exact completed work;
- exact partial work;
- exact blocked checks;
- files changed;
- commits;
- tests/typecheck/build status;
- database/migration status;
- real-device status;
- voice/translation status;
- UI visual verification status;
- business-vs-consumer verification status;
- security findings;
- next exact task.

Never claim PASS for a check that was not actually run.