# OPPA Mobile (Flutter)

The real V1 Flutter client for the OPPA API: phone → OTP → profile → chats →
wallet → payments → business → calls → me/security → support, with
Africa-first offline/reconnect behavior and the three OPPA themes.

## Status

- Source complete and API-integrated (real endpoints, real device-key step-up
  signing, durable offline queue).
- Flutter SDK was **not available** in the implementation environment, so
  `flutter analyze` / `flutter test` / release builds are **NOT RUN** — run
  them on a machine with the SDK before shipping (see Verification below).

## Architecture

```
lib/
  main.dart                    entrypoint (OPPA_API_URL dart-define)
  app.dart                     composition root (api/session/queue/repos/themes)
  core/
    api_client_base.dart       transport contract shared by real + demo layers
    api_client.dart            timeouts, retry classification, backoff+jitter
    demo_mode.dart             compile-time OPPA_DEMO_MODE constants (default OFF)
    demo_backend.dart          in-process demo backend (no network, demo OTP)
    connectivity_service.dart  online/reconnecting/offline state machine
    outbound_queue.dart        durable offline queue + secure token store
    screen_data.dart           cache-first loader with honest states
    session_store.dart         OTP verify, refresh rotation, logout
    device_key_manager.dart    EC P-256 device identity + step-up signing
  data/repositories.dart       typed repos matching the API exactly
  design/oppa_themes.dart      Fluid Africa / OPPA Pulse / Everyday OPPA
  ui/
    screens/auth_gate.dart     phone → OTP (demo hint) → voice-name → session
    screens/home_screens.dart  home, notifications, support/trust
    screens/chat_screens.dart  chats, thread (offline-pending sends), contacts
    screens/wallet_screens.dart balance, history, step-up transfer, funding
    screens/me_screens.dart    profile, themes, security posture, sign-out
    widgets/common.dart        StatusBanner + loading/empty/error views
```

## Demo mode (first APK without OTP providers)

A compile-time demo data layer exists for physical UI/UX testing. It performs
**no network I/O** and never sends the demo OTP (`000000`) anywhere; production
authentication is untouched. Demo mode is off by default and a product build
compiled with it refuses to start.

```bash
flutter build apk --debug --dart-define=OPPA_DEMO_MODE=true
```

Details and guardrails: `docs/MOBILE_DEMO_BUILD.md`. Codemagic workflows
(`oppa-mobile-demo`, `oppa-mobile-release`) live in the root `codemagic.yaml`;
Android platform scaffolding is generated on demand with
`sh ./scripts/prepare_android.sh`.

## Security model

- Access/refresh tokens and the device private key live in
  `flutter_secure_storage` (Android Keystore-backed). Never in
  SharedPreferences, never bundled.
- Device enrollment: EC P-256 keypair; the SPKI **public** PEM is the
  enrollment identifier sent at OTP verify; the server stores and later
  verifies step-up proofs against it.
- Money operations never use the offline queue. Transfers require the
  security-core step-up flow with an intent-bound ECDSA signature.
- No payment provider secrets exist in the app; funding opens the provider's
  hosted authorization page returned by the API.

## Running

```bash
flutter pub get
flutter run --dart-define=OPPA_API_URL=http://10.0.2.2:8080
```

The API must be reachable (its own env needs `DATABASE_URL` plus the auth
secrets — see the root `CODEX_HANDOFF.md`).

## Verification (honest)

| Gate | Status |
|---|---|
| `flutter analyze` | NOT RUN — Flutter SDK unavailable in implementation environment |
| `flutter test` | NOT RUN — same (new demo tests included: `test/demo_backend_test.dart`, `test/demo_mode_test.dart`) |
| Android release build | NOT RUN — same; scaffold with `sh ./scripts/prepare_android.sh` first |
| Demo-mode safety | Verified by inspection + tripwire tests; demo OTP never leaves the app process |
| Endpoint contract | Verified against `apps/api/src/modules/**/*-routes.ts` at implementation time |

Run `flutter analyze && flutter test` before merging UI changes on a machine
with the SDK, and record results in the root `CODEX_HANDOFF.md`.
