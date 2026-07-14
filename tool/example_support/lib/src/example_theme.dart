import 'package:flutter/material.dart';

/// Builds the shared restrained workbench theme used by every example app.
ThemeData buildKacheExampleTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF0F766E),
    brightness: brightness,
    surface: isDark ? const Color(0xFF111614) : const Color(0xFFF7F8F7),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 350),
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(color: scheme.onInverseSurface),
    ),
  );
}
