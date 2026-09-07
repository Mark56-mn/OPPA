import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";

import "app.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  const baseUrl = String.fromEnvironment(
    "OPPA_API_URL",
    defaultValue: "http://10.0.2.2:8080",
  );
  runApp(OppaApp(baseUrl: baseUrl, prefs: prefs));
}
