import 'package:flutter/material.dart';

import '../i18n/app_strings.dart';

class ThemePresetTokens {
  const ThemePresetTokens({
    required this.id,
    required this.displayName,
    required this.lightSeed,
    required this.darkSeed,
    required this.cornerRadius,
    required this.lightSurface,
    required this.darkSurface,
  });

  final String id;
  final String displayName;
  final Color lightSeed;
  final Color darkSeed;
  final double cornerRadius;
  final Color lightSurface;
  final Color darkSurface;
}

abstract final class ThemeRegistry {
  static const List<ThemePresetTokens> presets = <ThemePresetTokens>[
    ThemePresetTokens(
      id: 'material',
      displayName: AppStrings.themePresetMaterial,
      lightSeed: Color(0xFF1976D2),
      darkSeed: Color(0xFF90CAF9),
      cornerRadius: 12,
      lightSurface: Color(0xFFF8FAFD),
      darkSurface: Color(0xFF131A22),
    ),
    ThemePresetTokens(
      id: 'ios',
      displayName: AppStrings.themePresetIos,
      lightSeed: Color(0xFF0A84FF),
      darkSeed: Color(0xFF5AC8FA),
      cornerRadius: 16,
      lightSurface: Color(0xFFF5F7FA),
      darkSurface: Color(0xFF121418),
    ),
    ThemePresetTokens(
      id: 'claude',
      displayName: AppStrings.themePresetClaude,
      lightSeed: Color(0xFFB56E3B),
      darkSeed: Color(0xFFE6A87A),
      cornerRadius: 10,
      lightSurface: Color(0xFFF9F4EC),
      darkSurface: Color(0xFF1E1814),
    ),
  ];

  static ThemePresetTokens byId(String id) {
    return presets.firstWhere(
      (ThemePresetTokens preset) => preset.id == id,
      orElse: () => presets.first,
    );
  }
}
