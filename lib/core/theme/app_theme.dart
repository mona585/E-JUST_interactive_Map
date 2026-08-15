import 'package:flutter/material.dart';

/// Clean, modern theme for the Anyplace CampusFind application.
class AppTheme {
  AppTheme._();

  static const Color primary = Color(0xFF1E3A8A); // Deep Indigo
  static const Color primaryLight = Color(0xFF3B82F6); // Vibrant Blue
  static const Color accent = Color(0xFF0D9488); // Teal
  static const Color background = Color(0xFF0F172A); // Dark Slate
  static const Color surface = Color(0xFF1E293B); // Slate card surface
  static const Color surfaceLight = Color(0xFF334155);
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color markerColor = Color(0xFFEF4444); // Red/Coral marker
  static const Color markerSelected = Color(0xFFF59E0B); // Amber selected marker

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: primaryLight,
        secondary: accent,
        surface: surface,
        onSurface: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xCC0F172A),
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0x22FFFFFF), width: 1),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: surfaceLight,
        foregroundColor: textPrimary,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0x33FFFFFF), width: 1),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF1E293B),
        labelStyle: const TextStyle(color: textPrimary, fontSize: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: const BorderSide(color: Color(0x33FFFFFF)),
      ),
    );
  }
}
