import 'package:flutter/material.dart';

enum AppThemeMode { system, light, dark }

extension AppThemeModeX on AppThemeMode {
  ThemeMode toThemeMode() {
    return switch (this) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
    };
  }

  String get storageValue {
    return switch (this) {
      AppThemeMode.system => 'system',
      AppThemeMode.light => 'light',
      AppThemeMode.dark => 'dark',
    };
  }

  static AppThemeMode fromStorage(String raw) {
    return switch (raw) {
      'light' => AppThemeMode.light,
      'dark' => AppThemeMode.dark,
      _ => AppThemeMode.system,
    };
  }
}

class ThemeSelection {
  const ThemeSelection({required this.mode, required this.presetId});

  static const ThemeSelection defaults = ThemeSelection(
    mode: AppThemeMode.system,
    presetId: 'material',
  );

  final AppThemeMode mode;
  final String presetId;

  ThemeSelection copyWith({AppThemeMode? mode, String? presetId}) {
    return ThemeSelection(
      mode: mode ?? this.mode,
      presetId: presetId ?? this.presetId,
    );
  }
}
