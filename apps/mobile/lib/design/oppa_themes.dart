import "package:flutter/material.dart";

/// The three OPPA V1 themes. Theme changes visual tokens only — never
/// functionality. Tokens are central so components stay theme-agnostic.
enum OppaThemeId { fluidAfrica, pulse, everyday }

class OppaTokens {
  const OppaTokens({
    required this.id,
    required this.name,
    required this.seed,
    required this.primary,
    required this.onPrimary,
    required this.background,
    required this.surface,
    required this.onSurface,
    required this.accent,
    required this.success,
    required this.danger,
  });

  final OppaThemeId id;
  final String name;
  final Color seed;
  final Color primary;
  final Color onPrimary;
  final Color background;
  final Color surface;
  final Color onSurface;
  final Color accent;
  final Color success;
  final Color danger;
}

const oppaTokens = <OppaThemeId, OppaTokens>{
  OppaThemeId.fluidAfrica: OppaTokens(
    id: OppaThemeId.fluidAfrica,
    name: "Fluid Africa",
    seed: Color(0xFFB4530A),
    primary: Color(0xFFB4530A),
    onPrimary: Color(0xFFFFF8F4),
    background: Color(0xFF1A120B),
    surface: Color(0xFF2A1D12),
    onSurface: Color(0xFFF3E7DB),
    accent: Color(0xFFE8A44D),
    success: Color(0xFF3E9B5F),
    danger: Color(0xFFD4483B),
  ),
  OppaThemeId.pulse: OppaTokens(
    id: OppaThemeId.pulse,
    name: "OPPA Pulse",
    seed: Color(0xFF0B5FA5),
    primary: Color(0xFF0B5FA5),
    onPrimary: Color(0xFFF2F8FF),
    background: Color(0xFF0B1420),
    surface: Color(0xFF13202F),
    onSurface: Color(0xFFE2ECF6),
    accent: Color(0xFF39A0E5),
    success: Color(0xFF2FA46A),
    danger: Color(0xFFD4483B),
  ),
  OppaThemeId.everyday: OppaTokens(
    id: OppaThemeId.everyday,
    name: "Everyday OPPA",
    seed: Color(0xFF206A4D),
    primary: Color(0xFF206A4D),
    onPrimary: Color(0xFFF2FBF6),
    background: Color(0xFFF6F4EF),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF1C221E),
    accent: Color(0xFF3D8B6C),
    success: Color(0xFF2F8F55),
    danger: Color(0xFFC0392B),
  ),
};

/// Builds the Material theme from tokens (single source of truth).
ThemeData buildOppaTheme(OppaTokens t, {Brightness brightness = Brightness.dark}) {
  final scheme = ColorScheme(
    brightness: brightness,
    primary: t.primary,
    onPrimary: t.onPrimary,
    secondary: t.accent,
    onSecondary: t.onSurface,
    surface: t.surface,
    onSurface: t.onSurface,
    error: t.danger,
    onError: t.onPrimary,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.background,
    appBarTheme: AppBarTheme(
      backgroundColor: t.background,
      foregroundColor: t.onSurface,
      elevation: 0,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48), // accessible touch targets
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: t.onSurface.withOpacity(0.2)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
