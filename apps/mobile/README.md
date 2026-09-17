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
the Android platform folder (`android/`) is committed so CI builds are
reproducible — `sh ./scripts/prepare_android.sh` remains available to
regenerate it if it is ever removed or a new platform is added.

## Brand assets (OPPA Pulse)

The launcher icon, adaptive-icon layers and the launch splash are the OPPA
Pulse mark (glowing orb with three woven trails), rendered **from the same
geometry as the in-app vector painter** (`lib/design/oppa_brand.dart`). They
are generated PNGs (~250 KB total — no large binary assets):

```bash
python3 tools/generate_oppa_icons.py          # regenerate after brand changes
python3 tools/generate_oppa_icons.py --check  # CI-style freshness check
```

Requires `python3 -m pip install pillow numpy`. Never hand-edit the PNGs.

- `android/.../mipmap-*/ic_launcher.png` — launcher icons
- `android/.../mipmap-anydpi-v26/ic_launcher.xml` — adaptive icon
  (foreground `drawable/oppa_icon_foreground.png` on `@color/oppa_launch_bg`)
- `android/.../drawable/oppa_launch.png` — centered OPPA PULSE splash shown
  by `LaunchTheme` until Flutter draws its first frame

## Onboarding (8 steps, matching the approved art)

`Welcome → phone → OTP → profile (speak/type your name) → profile picture →
Choose your OPPA ID → Choose Your OPPA Look → security → You're all set!`

- **OPPA ID is real.** Three candidates are derived from the name and each is
  checked against `GET /profile/oppa-id/available/:id`; free text is
  debounce-checked. `Continue` stays disabled until the **server** reports the
  handle available, and `POST /profile/oppa-id` performs the claim. A rejected
  claim (taken in a race / reserved / rate-limited) keeps you on the step with
  the server's reason — the client never decides availability.
- **Profile picture is honestly locked.** There is no media-upload endpoint in
  V1, so Camera/Gallery explain that instead of writing a fake `avatarUrl`.
- **Security step** reports only what is true (this device really is enrolled
  by OTP verify); app-lock PIN, biometrics and 2FA are marked as not shipped.

## Themes (three approved looks)

`OppaThemeId` = **OPPA Pulse** (purple, dark) · **Fluid Africa** (amber, dark) ·
**Everyday OPPA** (green, **light**). Each token set carries its own
`brightness`, so the light look is built as a light `ColorScheme`.

The choice is persisted under `oppa.themeId` (`ThemePreference`) and restored
before the first frame. Theme is presentation only — it never touches identity,
chats, wallet or security.

## Workspaces (one OPPA identity)

Personal (Chats/Wallet/Calls/Me) and Business (Dashboard/Orders/Products/More)
are separate surfaces behind one session — switching never logs you out. The
Business app is a fullscreen route and always offers **Back to Personal**.
Creating a store is a real `POST /business`; the new store owns its own
products, orders and roster and starts empty. Merchants can add, edit, archive
and restore products (`PATCH /business/:id/products/:productId`) and rename the
store (`PATCH /business/:id`, owner-only). "Message customer" hands off to the
personal Chats tab and opens the real direct conversation.

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
| `flutter analyze` | PASS — No issues found (SDK at `/tmp/flutter`) |
| `flutter test` | PASS — 52/52 (incl. `session_bootstrap_test`, `startup_ui_test` widget tests, `demo_backend_test`, `demo_mode_test`) |
| Define-positive demo check | PASS — `flutter test --dart-define=OPPA_DEMO_MODE=true test/demo_mode_test.dart` (CI runs it before the APK build) |
| Startup regression | PASS — widget tests prove fresh start reaches `AuthGate`, never a permanent spinner; storage failure/timeout → visible Retry UI (fail closed) |
| Android debug APK | Via Codemagic `oppa-mobile-demo` (committed `android/` platform); local device build BLOCKED — no Android SDK here |
| Demo-mode safety | Verified by inspection + tripwire tests; demo OTP never leaves the app process |
| Endpoint contract | Verified against `apps/api/src/modules/**/*-routes.ts` at implementation time |

Run `flutter analyze && flutter test` before merging UI changes on a machine
with the SDK, and record results in the root `CODEX_HANDOFF.md`.
