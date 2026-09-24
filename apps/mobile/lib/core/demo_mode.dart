/// Compile-time demo configuration for OPPA mobile.
///
/// SAFETY MODEL (see docs/MOBILE_DEMO_BUILD.md):
/// - [enabled] is a compile-time constant from `--dart-define=OPPA_DEMO_MODE=true`.
///   It is NOT a runtime switch: no UI, preference, or server response can flip it.
/// - The default is `false`, so a normal `flutter build` / `flutter run` always
///   produces a production-safe binary.
/// - Demo mode replaces the app's data layer (see `demo_backend.dart`): the demo
///   build never opens a network connection to the OPPA API, so a demo OTP can
///   never reach production authentication.
/// - Production authentication is untouched: the real `SessionStore` still posts
///   to `/auth/otp/verify`, and the backend still rejects the demo code with
///   OTP_INVALID_OR_EXPIRED because it is simply a wrong code.
///
/// DEMO MODE IS NOT PRODUCTION AUTHENTICATION.
class DemoMode {
  const DemoMode._();

  /// Enable ONLY in development builds:
  ///   flutter run --dart-define=OPPA_DEMO_MODE=true
  static const bool enabled =
      bool.fromEnvironment("OPPA_DEMO_MODE", defaultValue: false);

  /// The development-only OTP shown on the demo verification screen. It exists
  /// ONLY inside the demo backend in this app process; production APIs never
  /// receive or accept it.
  static const String demoOtp = "000000";

  /// Visible development indicator drawn over the whole app when enabled.
  static const String bannerLabel = "DEMO BUILD";

  /// True when running in an AOT/product (release or profile) build. Used by
  /// the startup guard in app.dart so a release binary can never boot with
  /// demo mode compiled in.
  static const bool isProductBuild =
      bool.fromEnvironment("dart.vm.product", defaultValue: false);
}
