import 'package:flutter/material.dart';

ThemeData buildLightTheme(Color accent) {
  final onAccent = Colors.white; // good default for strong accents

  final scheme = const ColorScheme.light().copyWith(
    primary: accent,            // ← exact color
    onPrimary: onAccent,
    secondary: accent,          // use same accent for secondary
    onSecondary: onAccent,

    // keep neutrals stable so accent “pops”
    surface: const Color(0xFFF9F7F7),
    onSurface: const Color(0xFF111111),
    background: const Color(0xFFF9F7F7),
    onBackground: const Color(0xFF111111),

    // optional: use exact accent for containers too (keeps things punchy)
    primaryContainer: accent,
    onPrimaryContainer: onAccent,
    secondaryContainer: accent,
    onSecondaryContainer: onAccent,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.background,

    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0.5,
      surfaceTintColor: Colors
          .transparent, // ← prevents Material 3 from tinting with primary
      iconTheme: IconThemeData(color: scheme.onSurface),
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.primary,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),

    // optional: make chips/buttons default to accent
    chipTheme: ChipThemeData(
      selectedColor: scheme.primary.withOpacity(.18),
      checkmarkColor: scheme.onPrimary,
      labelStyle: TextStyle(color: scheme.onSurface),
    ),
  );
}

ThemeData buildDarkTheme(Color accent) {
  final onAccent = Colors.white;

  final scheme = const ColorScheme.dark().copyWith(
    primary: accent,            // ← exact color
    onPrimary: onAccent,
    secondary: accent,
    onSecondary: onAccent,

    surface: const Color(0xFF1C1C1C),
    onSurface: Colors.white,
    background: const Color(0xFF121212),
    onBackground: Colors.white,

    primaryContainer: accent,
    onPrimaryContainer: onAccent,
    secondaryContainer: accent,
    onSecondaryContainer: onAccent,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.background,

    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0.5,
      surfaceTintColor: Colors.transparent, // ← no automatic tint
      iconTheme: IconThemeData(color: scheme.onSurface),
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.primary,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );
}
