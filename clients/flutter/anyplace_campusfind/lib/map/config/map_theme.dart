import 'package:flutter/material.dart';

/// Dark-slate theme used by the map stack (markers, controls, cards).
///
/// Ported from the map_refactor branch. Named `MapTheme` (instead of the
/// original `AppTheme`) so it does not collide with the CampusFind app's own
/// light `AppTheme` in `config/theme.dart` — the map keeps its dark look while
/// the rest of the app keeps its light theme.
class MapTheme {
  MapTheme._();

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
}
