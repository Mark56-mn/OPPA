# OPPA mobile — safe demo mode for the first APK

## Why this exists

The first real Android APK build needs to exercise the **complete Flutter UI** —
onboarding, chats, wallet, business, calls, notifications, offline states — on a
physical device **without waiting for production OTP provider credentials**.

This document describes the isolated demo mode that makes that possible without
touching production authentication.

## Safety model (non-negotiable invariants)

- **Compile-time only.** Demo mode is `bool.fromEnvironment("OPPA_DEMO_MODE", defaultValue: false)`.
  There is no runtime switch, preference, server response, or hidden gesture that
  can enable it. See `apps/mobile/lib/core/demo_mode.dart`.
- **In-process backend.** Demo builds use `DemoBackend` (see
  `apps/mobile/lib/core/demo_backend.dart`), which implements the same
  transport contract (`ApiClientBase`) as the real HTTP client. It performs **no
  network I/O** — the demo OTP is checked inside the app process against a
  compiled-in constant, so a demo code can never reach production authentication.
- **Production code paths untouched.** No production route accepts a fake or
  universal OTP. No OTP validation is disabled. Session security, device
  enrollment and token verification are unchanged. The real `SessionStore`
  posts to `/auth/otp/verify` exactly as before; in production the demo code is
  simply a wrong code and is rejected with `OTP_INVALID_OR_EXPIRED`.
- **Product-build guard.** If a release/AOT binary is somehow compiled with
  `OPPA_DEMO_MODE=true`, the app refuses to boot and shows a configuration
  error (`dart.vm.product` check in `app.dart`). Fail closed.
- **Visible demo indicator.** Demo builds draw an amber `DEMO BUILD` banner on
  every screen and label all demo flows. No demo state pretends to be real.
- **No secrets.** The demo backend ships no provider credentials and no
  production URLs. Payment authorization in demo mode opens
  `https://demo.invalid/…` and never transmits anything.

## Building the demo APK

```bash
cd apps/mobile
flutter pub get
flutter build apk --debug \
  --dart-define=OPPA_DEMO_MODE=true \
  --dart-define=OPPA_API_URL=http://10.0.2.2:8080
```

`OPPA_API_URL` is **ignored** in demo mode (no network is used); it only
matters for production builds pointing at a real API.

Install on a device:

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

## Building a production-safe APK

Any build **without** the demo define is production-safe:

```bash
flutter build apk --release
```

The release workflow in `codemagic.yaml` deliberately runs **without**
`OPPA_DEMO_MODE` and additionally asserts the demo default is `false` in tests
(`test/demo_mode_test.dart`).

## Demo coverage

| Area | Demo behavior |
| --- | --- |
| Auth | Phone → OTP (`000000`, shown on screen) → voice/typed name → session |
| Profile/OPPA ID | Claim `oppa_id`, availability checks, reserved-name rejection |
| Chats | Seeded conversations, send/read receipts, offline pending bubbles |
| Calls | Audio lifecycle start → ring → answer → hang up; seeded incoming call |
| Wallet | Local ledger with deterministic third-transfer failure to exercise error states |
| Payments | Simulated authorization URL + seeded pending/successful/failed history |
| Business | Products, orders, analytics, staff, self-order blocker (mirrors server) |
| Notifications | Read/unread, preferences |
| Offline | `queuePendingMessage` seeds pending sends for the reconnect path |

## Codemagic

`codemagic.yaml` defines two workflows:

- `oppa-mobile-demo` — debug APK with `--dart-define=OPPA_DEMO_MODE=true`,
  published as an artifact for physical UI/UX testing.
- `oppa-mobile-release` — release APK **without** demo defines; runs the full
  test suite first so the compile-time-off tripwires execute.

No signing credentials are required for debug builds; release signing expects
the CodeMagic `keystore` variable group (documented inline) before store
distribution.
