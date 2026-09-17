import "package:flutter/material.dart";
import "package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

import "package:oppa_mobile/app.dart";
import "package:oppa_mobile/core/demo_backend.dart";
import "package:oppa_mobile/design/oppa_themes.dart";
import "package:oppa_mobile/ui/screens/business_app.dart";

/// End-to-end merchant journey on the demo transport: switch workspace →
/// create a business → land in the Business app → see the new (empty) store.
/// This is the flow that used to silently do nothing.
void main() {
  Future<void> signIn(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, "Phone number"), "+2348012345678");
    await tester.tap(find.text("Continue"));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, "6-digit code"), "000000");
    await tester.tap(find.text("Verify"));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text("Skip — add it later"));
    await tester.tap(find.text("Skip — add it later"));
    await tester.pumpAndSettle();
    // Walk the remaining onboarding steps to Home: picture, OPPA ID, the
    // OPPA Look and the security step each have exactly one Continue.
    for (var i = 0; i < 4; i++) {
      await tester.ensureVisible(find.text("Continue"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Continue"));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.text("Start OPPA"));
    await tester.tap(find.text("Start OPPA"), warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  Future<void> pumpDemo(WidgetTester tester,
      {Map<String, Object> initialPrefs = const {}}) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    // main.dart always hands the app its SharedPreferences instance; the theme
    // preference can only be restored when the app is given one.
    final prefs = await SharedPreferences.getInstance();
    FlutterSecureStoragePlatform.instance = _MemorySecurePlatform();
    await tester.pumpWidget(OppaApp(
      baseUrl: "http://localhost:1",
      prefs: prefs,
      apiForTesting: DemoBackend(latency: Duration.zero),
    ));
  }

  testWidgets("a merchant can create a business and lands in its own workspace",
      (tester) async {
    await pumpDemo(tester);
    await signIn(tester);

    // Open the workspace switcher from the Chats header.
    await tester.tap(find.byIcon(Icons.swap_horiz_outlined));
    await tester.pumpAndSettle();
    expect(find.text("Switch workspace"), findsOneWidget);
    expect(find.text("Personal"), findsOneWidget);
    // The seed store is listed (this only works because GET /business routes).
    expect(find.text("Kano Spices Demo"), findsOneWidget);

    await tester.tap(find.text("Create a Business"));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, "Mama's Kitchen");
    await tester.tap(find.text("Create"));
    await tester.pumpAndSettle();

    // The Business workspace opens, titled with the REAL created store.
    expect(find.byType(BusinessApp), findsOneWidget);
    expect(find.text("Mama's Kitchen"), findsWidgets);
    expect(find.widgetWithText(NavigationDestination, "Dashboard"),
        findsOneWidget);
    expect(find.widgetWithText(NavigationDestination, "Products"),
        findsOneWidget);

    // A brand-new store owns no catalogue: no inherited products.
    await tester.tap(find.widgetWithText(NavigationDestination, "Products"));
    await tester.pumpAndSettle();
    expect(
        find.text(
            "No products yet — add your first item so customers can order"),
        findsOneWidget);
  });

  testWidgets("the created business is listed on the way back (real persistence)",
      (tester) async {
    await pumpDemo(tester);
    await signIn(tester);

    await tester.tap(find.byIcon(Icons.swap_horiz_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Create a Business"));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, "Ada's Boutique");
    await tester.tap(find.text("Create"));
    await tester.pumpAndSettle();

    // Leave the merchant workspace (the AppBar close action is the only way
    // out of the fullscreen Business app) and reopen the switcher.
    await tester.tap(find.byTooltip("Back to Personal"));
    await tester.pumpAndSettle();
    expect(find.byType(BusinessApp), findsNothing);
    await tester.tap(find.byIcon(Icons.swap_horiz_outlined));
    await tester.pumpAndSettle();

    expect(find.text("Ada's Boutique"), findsOneWidget,
        reason: "the new business must be listed, not just navigated into");
    expect(find.text("Kano Spices Demo"), findsOneWidget);
  });

  testWidgets("the chosen OPPA Look is restored on the next launch",
      (tester) async {
    // Pre-seed the stored preference and verify the app boots into it: the
    // look used to reset to the default on every start.
    await pumpDemo(tester, initialPrefs: {
      ThemePreference.storageKey:
          ThemePreference.encode(OppaThemeId.everyday)
    });
    await tester.pumpAndSettle();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.colorScheme.brightness, Brightness.light,
        reason: "Everyday OPPA is the approved light look");
    expect(app.theme!.colorScheme.primary, oppaTokens[OppaThemeId.everyday]!.primary);
  });
}

/// In-memory secure storage so the auth bootstrap works in tests.
class _MemorySecurePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> _store = {};

  @override
  Future<bool> containsKey(
          {required String key, required Map<String, String> options}) async =>
      _store.containsKey(key);

  @override
  Future<void> delete(
      {required String key, required Map<String, String> options}) async {
    _store.remove(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      _store.clear();

  @override
  Future<String?> read(
          {required String key, required Map<String, String> options}) async =>
      _store[key];

  @override
  Future<Map<String, String>> readAll(
          {required Map<String, String> options}) async =>
      Map.of(_store);

  @override
  Future<void> write(
      {required String key,
      required String value,
      required Map<String, String> options}) async {
    _store[key] = value;
  }
}
