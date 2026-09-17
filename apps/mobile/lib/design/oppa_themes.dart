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
    this.brightness = Brightness.dark,
  });

  final OppaThemeId id;
  final String name;

  /// Lightness of the palette itself — NOT a user preference. "Everyday OPPA"
  /// is the approved light look, so it must be built as a light ColorScheme;
  /// forcing a dark scheme over white surfaces produced unreadable
  /// white-on-white text before this field existed.
  final Brightness brightness;
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

/// Token sets aligned to the approved "Choose Your OPPA Look" screens:
/// Fluid Africa = warm amber/gold on deep brown, OPPA Pulse = brand violet
/// on near-black, Everyday OPPA = clean green on white.
/// Durable storage for the chosen look. The theme is presentation only, so it
/// lives in plain preferences (never secure storage) and survives restarts —
/// a user should not have to re-pick their look every time OPPA opens.
class ThemePreference {
  const ThemePreference._();

  static const storageKey = "oppa.themeId";

  /// Parses a stored value, falling back to the default look for unknown or
  /// missing values (a renamed/removed look must never crash startup).
  static OppaThemeId decode(String? stored) {
    for (final id in OppaThemeId.values) {
      if (id.name == stored) return id;
    }
    return defaultThemeId;
  }

  static String encode(OppaThemeId id) => id.name;

  /// Approved default: the OPPA Pulse dark look.
  static const defaultThemeId = OppaThemeId.pulse;
}

const oppaTokens = <OppaThemeId, OppaTokens>{
  OppaThemeId.fluidAfrica: OppaTokens(
    id: OppaThemeId.fluidAfrica,
    name: "Fluid Africa",
    seed: Color(0xFFF59E0B),
    primary: Color(0xFFF59E0B),
    onPrimary: Color(0xFF231303),
    background: Color(0xFF171008),
    surface: Color(0xFF241A0D),
    onSurface: Color(0xFFF6ECDD),
    accent: Color(0xFFFBBF24),
    success: Color(0xFF3E9B5F),
    danger: Color(0xFFEF5350),
  ),
  OppaThemeId.pulse: OppaTokens(
    id: OppaThemeId.pulse,
    name: "OPPA Pulse",
    seed: Color(0xFF7C3AED),
    primary: Color(0xFF7C3AED),
    onPrimary: Color(0xFFFFFFFF),
    background: Color(0xFF0B0213),
    surface: Color(0xFF171022),
    onSurface: Color(0xFFEDE6F7),
    accent: Color(0xFFA78BFA),
    success: Color(0xFF34D399),
    danger: Color(0xFFF87171),
  ),
  OppaThemeId.everyday: OppaTokens(
    id: OppaThemeId.everyday,
    name: "Everyday OPPA",
    brightness: Brightness.light,
    seed: Color(0xFF16A34A),
    primary: Color(0xFF16A34A),
    onPrimary: Color(0xFFFFFFFF),
    background: Color(0xFFF7FAF5),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF14231A),
    accent: Color(0xFF22C55E),
    success: Color(0xFF16A34A),
    danger: Color(0xFFDC2626),
  ),
};

/// Builds the Material theme from tokens (single source of truth).
/// Defaults to the palette's own lightness so every call site gets a
/// readable scheme without having to remember which look is light.
ThemeData buildOppaTheme(OppaTokens t, {Brightness? brightness}) {
  final scheme = ColorScheme(
    brightness: brightness ?? t.brightness,
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
    cardTheme: CardThemeData(
      color: t.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: t.onSurface.withValues(alpha: 0.08)),
      ),
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
        borderSide: BorderSide(color: t.onSurface.withValues(alpha: 0.2)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
