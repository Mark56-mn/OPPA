import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

import "package:oppa_mobile/app.dart";
import "package:oppa_mobile/core/demo_backend.dart";
import "package:oppa_mobile/core/demo_mode.dart";
import "package:oppa_mobile/ui/screens/auth_gate.dart";

/// In-memory secure-storage platform shared with the app under test.
class _MemorySecurePlatform extends FlutterSecureStoragePlatform {
  _MemorySecurePlatform(this.values);

  final Map<String, String> values;
  Completer<void>? gate;

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      values.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    values.remove(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    values.clear();
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    final g = gate;
    if (g != null) await g.future;
    return values[key];
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      Map.of(values);

  @override
  Future<void> write({
    required String key,
    required String? value,
    required Map<String, String> options,
  }) async {
    values[key] = value ?? "";
  }
}

Future<void> _pumpApp(WidgetTester tester, {bool demoTransport = false}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStoragePlatform.instance = _MemorySecurePlatform({});
  await tester.pumpWidget(OppaApp(
    baseUrl: "http://localhost:1",
    // Widget tests run without the demo define; when a test needs the full
    // demo flow, it injects the in-process demo backend explicitly.
    apiForTesting: demoTransport ? DemoBackend() : null,
  ));
}

void main() {
  testWidgets(
    "demo APK startup: AuthGate is shown, not the startup spinner",
    (tester) async {
      expect(DemoMode.enabled, isFalse, reason: "test default is production");
      await _pumpApp(tester);
      // Let bootstrap settle (storage read + phase event + rebuild).
      await tester.pumpAndSettle();

      // THE regression: the first APK spun forever here. The startup path must
      // land on the auth UI, never a bare CircularProgressIndicator.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(AuthGate), findsOneWidget);
      expect(find.text("Send code"), findsOneWidget);
    },
  );

  testWidgets(
    "production default is identical: AuthGate on a fresh install",
    (tester) async {
      // Same build (DemoMode.enabled == false — tests never set the define),
      // proving the fix is not demo-specific.
      await _pumpApp(tester);
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(AuthGate), findsOneWidget);
      // No demo banner exists in a production configuration.
      expect(find.text(DemoMode.bannerLabel), findsNothing);
    },
  );

  testWidgets(
    "secure-storage failure shows the visible error + Retry, never a spinner",
    (tester) async {
      final broken = _BrokenSecurePlatform();
      FlutterSecureStoragePlatform.instance = broken;
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const OppaApp(baseUrl: "http://localhost:1"));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(AuthGate), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text("Retry"), findsOneWidget);

      // Retry recovers once storage works again (fail closed → recover).
      FlutterSecureStoragePlatform.instance = _MemorySecurePlatform({});
      await tester.tap(find.text("Retry"));
      await tester.pumpAndSettle();

      expect(find.byType(AuthGate), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    "restart after login goes straight to Home (stored refresh token)",
    (tester) async {
      final platform = _MemorySecurePlatform({
        "oppa.refresh_token": "stored-refresh-token",
      });
      FlutterSecureStoragePlatform.instance = platform;
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const OppaApp(baseUrl: "http://localhost:1"));
      await tester.pumpAndSettle();

      // Authenticated from storage → the 4-tab personal shell, no AuthGate.
      expect(find.byType(AuthGate), findsNothing);
      expect(find.widgetWithText(Tab, "Home"), findsOneWidget);
      expect(find.widgetWithText(Tab, "Chats"), findsOneWidget);
      expect(find.widgetWithText(Tab, "Wallet"), findsOneWidget);
      expect(find.widgetWithText(Tab, "Me"), findsOneWidget);
    },
  );

  testWidgets(
    "demo flow: phone entry → demo OTP (000000) → profile → Home",
    (tester) async {
      // This widget test runs without the demo define, so it injects the
      // in-process demo backend explicitly (same class the real demo APK uses,
      // minus the compile-time gate). It exercises the exact code path:
      // SessionStore.requestOtp/verifyOtp → AuthGate steps → HomeShell.
      await _pumpApp(tester, demoTransport: true);
      await tester.pumpAndSettle();

      // 1. Phone entry.
      await tester.enterText(
          find.widgetWithText(TextField, "Phone number"), "+2348012345678");
      await tester.tap(find.text("Send code"));
      await tester.pumpAndSettle();

      // 2. OTP screen.
      expect(find.text("6-digit code"), findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextField, "6-digit code"), "000000");
      await tester.tap(find.text("Verify and continue"));
      await tester.pumpAndSettle();

      // 3. Profile step appears (voice name entry screen).
      expect(find.text("What should we call you?"), findsOneWidget);
      // 4. Skip onboarding → the authenticated Home shell.
      await tester.tap(find.text("Skip for now"));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Tab, "Home"), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );
}

/// Platform fake whose every operation throws — models a broken keystore.
class _BrokenSecurePlatform extends FlutterSecureStoragePlatform {
  Never _fail() => throw StateError("secure storage unavailable");

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      _fail();

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) =>
      Future.error(_fail());

  @override
  Future<void> deleteAll({required Map<String, String> options}) =>
      Future.error(_fail());

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async =>
      _fail();

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      _fail();

  @override
  Future<void> write({
    required String key,
    required String? value,
    required Map<String, String> options,
  }) =>
      Future.error(_fail());
}
