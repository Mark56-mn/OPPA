import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";

import "app.dart";

Future<void> main() async {
  debugPrint("OPPA.main: binding init");
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint("OPPA.main: binding ready");
  debugPrint("OPPA.main: SharedPreferences read");
  final prefs = await SharedPreferences.getInstance();
  debugPrint("OPPA.main: prefs ready (${prefs.getKeys().length} keys)");
  const baseUrl = String.fromEnvironment(
    "OPPA_API_URL",
    defaultValue: "http://10.0.2.2:8080",
  );
  debugPrint("OPPA.main: runApp (demo=${const bool.fromEnvironment("OPPA_DEMO_MODE")})");
  runApp(OppaApp(baseUrl: baseUrl, prefs: prefs));
}
