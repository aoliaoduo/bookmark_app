class AppSettings {
  const AppSettings({
    required this.deviceId,
    required this.titleRefreshDays,
    required this.autoRefreshOnLaunch,
    required this.webDavEnabled,
    required this.webDavBaseUrl,
    required this.webDavUserId,
    required this.webDavUsername,
    required this.webDavPassword,
  });

  final String deviceId;
  final int titleRefreshDays;
  final bool autoRefreshOnLaunch;
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
      webDavEnabled: webDavEnabled ?? this.webDavEnabled,
      webDavBaseUrl: webDavBaseUrl ?? this.webDavBaseUrl,
      webDavUserId: webDavUserId ?? this.webDavUserId,
      webDavUsername: webDavUsername ?? this.webDavUsername,
      webDavPassword: webDavPassword ?? this.webDavPassword,
    );
  }
}
