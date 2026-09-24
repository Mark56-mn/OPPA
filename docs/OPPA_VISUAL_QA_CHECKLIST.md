# OPPA Flutter visual QA checklist

**Branch:** `oppa-mobile-demo`  
**Reference authority:** supplied OPPA boards; the approved OPPA Pulse orb/wordmark is not replaced.

## How to read this checklist

- **PASS (code-verified):** the screen uses the implemented OPPA component/theme system and the available Flutter analysis/tests pass. This is not a substitute for device screenshot comparison.
- **NEEDS WORK:** the screen is still using legacy Material styling, is only partially aligned, or has not received a responsive/device pass.
- **BLOCKED:** a real APK/device/runtime is required to verify the state honestly.

## Reference-board coverage

| Reference area / screen | Status | Evidence and remaining work |
|---|---|---|
| Welcome to OPPA | PASS (code-verified) | Official in-app vector Pulse orb/wordmark, branded CTA, theme tokens, responsive gutter. Device comparison still pending. |
| Enter phone number | PASS (code-verified) | Shared input treatment, validation, disabled/busy states, keyboard-safe page. Device comparison still pending. |
| Verify phone / OTP | PASS (code-verified) | Six-digit input, completion-gated CTA, error surface, back navigation, real production auth. |
| Create profile | PASS (code-verified) | Shared step header/progress rail and primary action. |
| Choose profile picture | PASS (code-verified) | Honest locked state retained; no fake upload flow. |
| Choose OPPA ID | PASS (code-verified) | Real availability/claim flow and failure states. |
| Choose OPPA Look | PASS (code-verified) | Three shared themes persist without changing identity or backend behavior. |
| Completion | PASS (code-verified) | Completion CTA and honest handoff into the authenticated shell. |
| Home | PASS (code-verified) | Branded header, real balance, Last-known cache label, quick actions, activity/loading/offline/error states. |
| Personal bottom navigation | PASS (code-verified) | Chats · Wallet · Calls · Me with themed glowing active pill, 48dp+ targets, safe area, test key/semantics. |
| Chats list | NEEDS WORK | Real list/search/unread/read receipts are preserved; visual rollout to the shared cards/avatars/pills is pending. |
| Chat thread and composer | NEEDS WORK | Real messaging, failed/retry/voice/translation paths are preserved; reference-aligned bubbles, composer, and message details still need rollout. |
| Message details / receipts | NEEDS WORK | Backend receipts and projected `mine` are real; visual detail sheet still needs the shared design system. |
| Contacts / Connect | NEEDS WORK | Real contacts, lookup, and connect paths are present; reference-aligned search/filter/contact cards still need rollout. |
| Calls | NEEDS WORK | Real signaling/lifecycle/history and honest media-unavailable state are preserved; full call-screen visual pass remains. |
| Wallet | NEEDS WORK | Real server-authoritative balance/history/detail architecture is preserved; shared-card rollout and all reference payment states still need device QA. |
| Business dashboard | NEEDS WORK | Real workspace, products, orders, staff, analytics, and settings are present; shared themed component rollout remains. |
| Merchant chat / translator | NEEDS WORK | Real business conversation/translator entry points are preserved; reference composition still needs visual alignment. |
| Notifications | NEEDS WORK | Real categories, unread counts, read state, preferences, and deep links are present; reference-aligned list/filter cards remain. |
| Profile / Me | NEEDS WORK | Real profile/OPPA ID/privacy/security entry points exist; shared list/card styling remains to be completed. |
| Security center | NEEDS WORK | Existing security controls and honest locks are preserved; themed devices/session/2FA/biometric states still need visual QA. |
| Settings / Support | NEEDS WORK | Real destinations and locked feature states exist; final reference-aligned settings/support polish remains. |
| Offline / low-data | BLOCKED (device QA) | Existing connectivity queue and honest cached/offline messaging are wired; airplane-mode and low-data verification requires an APK/device. |
| Responsive 360dp and large Android phones | BLOCKED (device QA) | Shared page/gutter helpers are implemented and widget tests pass; no Android device/emulator is available here. |
| Android launcher icon and splash | PASS (code-verified) | Approved OPPA Pulse vector geometry is generated into the Android assets and guarded by `tools/check_brand_assets.py`; APK rendering still pending. |
| Visual QA against every supplied board | NEEDS WORK | No Android SDK/emulator/device is available in this environment, so screenshot-by-screenshot comparison cannot honestly be marked complete. |

## Current verification

- `flutter analyze`: **PASS** — no issues found.
- `flutter test`: **PASS** — 72 passed, 2 skipped by design (demo define-gated tests).
- `flutter test test/startup_ui_test.dart`: **PASS**.
- Android APK build/on-device visual pass: **BLOCKED** — no Java/Android SDK/device in this environment; Codemagic must run the existing APK workflow.
- Reference-board screenshot comparison: **BLOCKED** until the APK is installed on a real Android device or emulator.
