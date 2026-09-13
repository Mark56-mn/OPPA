import "package:flutter_test/flutter_test.dart";

import "package:oppa_mobile/core/demo_mode.dart";

/// Positive verification that `--dart-define=OPPA_DEMO_MODE=true` actually
/// flips the compiled-in switch.
///
/// The default `flutter test` command runs WITHOUT the define, so the
/// define-positive tests are skipped automatically (skipped = passing, not
/// failing). Run the enabled variant explicitly with:
///
///   flutter test --dart-define=OPPA_DEMO_MODE=true test/demo_mode_test.dart
///
/// This is exactly the compile-time flag the demo APK is built with, so a
/// passing run here proves the APK build command reaches the app with demo
/// mode enabled. CI runs both variants.
const String? _needsDefine = bool.fromEnvironment("OPPA_DEMO_MODE")
    ? null
    : "runs only with --dart-define=OPPA_DEMO_MODE=true (CI matrix)";

void main() {
  test("demo mode is a compile-time constant matching the build define", () {
    // In the default run this asserts OFF (production safety). In the
    // --dart-define=OPPA_DEMO_MODE=true run it asserts ON, proving the
    // define actually reaches compiled code (the same flag the demo APK
    // build passes).
    expect(DemoMode.enabled, const bool.fromEnvironment("OPPA_DEMO_MODE"));
  });

  test("demo OTP is a development-only 6-digit constant", () {
    expect(DemoMode.demoOtp, hasLength(6));
    expect(int.tryParse(DemoMode.demoOtp), isNotNull);
  }, skip: _needsDefine);

  test("with the define, the demo OTP is the documented 000000", () {
    expect(DemoMode.demoOtp, "000000");
  }, skip: _needsDefine);

  test("banner label is defined for the visible demo indicator", () {
    expect(DemoMode.bannerLabel, isNotEmpty);
  });
}
