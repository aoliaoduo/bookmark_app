import 'package:flutter/material.dart';

enum AppThemePreference {
  system,
  light,
  dark;

  ThemeMode get themeMode {
    switch (this) {
      case AppThemePreference.system:
        return ThemeMode.system;
      case AppThemePreference.light:
        return ThemeMode.light;
      case AppThemePreference.dark:
        return ThemeMode.dark;
    }
  }

  String get label {
    switch (this) {
      case AppThemePreference.system:
        return '跟随系统';
      case AppThemePreference.light:
        return '浅色';
      case AppThemePreference.dark:
        return '深色';
    }
  }

  static AppThemePreference fromStorage(String? raw) {
    for (final AppThemePreference item in AppThemePreference.values) {
      if (item.name == raw) {
        return item;
      }
    }
    return AppThemePreference.system;
  }
}

class AppSettings {
  const AppSettings({
    required this.deviceId,
    required this.titleRefreshDays,
    required this.autoRefreshOnLaunch,
    required this.autoSyncOnLaunch,
    required this.autoSyncOnChange,
    this.themePreference = AppThemePreference.system,
    required this.webDavEnabled,
    required this.webDavBaseUrl,
    required this.webDavUserId,
    required this.webDavUsername,
    required this.webDavPassword,
  });

  final String deviceId;
  final int titleRefreshDays;
  final bool autoRefreshOnLaunch;
  final bool autoSyncOnLaunch;
  final bool autoSyncOnChange;
  final AppThemePreference themePreference;
  final bool webDavEnabled;
  final String webDavBaseUrl;
  final String webDavUserId;
  final String webDavUsername;
  final String webDavPassword;

  bool get syncReady {
    return webDavEnabled &&
        webDavBaseUrl.trim().isNotEmpty &&
        webDavUserId.trim().isNotEmpty &&
        webDavUsername.trim().isNotEmpty &&
        webDavPassword.isNotEmpty;
  }

  AppSettings copyWith({
    String? deviceId,
    int? titleRefreshDays,
    bool? autoRefreshOnLaunch,
    bool? autoSyncOnLaunch,
    bool? autoSyncOnChange,
    AppThemePreference? themePreference,
    bool? webDavEnabled,
    String? webDavBaseUrl,
    String? webDavUserId,
    String? webDavUsername,
    String? webDavPassword,
  }) {
    return AppSettings(
      deviceId: deviceId ?? this.deviceId,
      titleRefreshDays: titleRefreshDays ?? this.titleRefreshDays,
      autoRefreshOnLaunch: autoRefreshOnLaunch ?? this.autoRefreshOnLaunch,
      autoSyncOnLaunch: autoSyncOnLaunch ?? this.autoSyncOnLaunch,
      autoSyncOnChange: autoSyncOnChange ?? this.autoSyncOnChange,
      themePreference: themePreference ?? this.themePreference,
      webDavEnabled: webDavEnabled ?? this.webDavEnabled,
      webDavBaseUrl: webDavBaseUrl ?? this.webDavBaseUrl,
      webDavUserId: webDavUserId ?? this.webDavUserId,
      webDavUsername: webDavUsername ?? this.webDavUsername,
      webDavPassword: webDavPassword ?? this.webDavPassword,
    );
  }
}
