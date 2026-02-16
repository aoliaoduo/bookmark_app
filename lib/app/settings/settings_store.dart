import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'app_settings.dart';

class SettingsStore {
  static const String _deviceIdKey = 'device_id';
  static const String _titleRefreshDaysKey = 'title_refresh_days';
  static const String _autoRefreshOnLaunchKey = 'auto_refresh_on_launch';
  static const String _webDavEnabledKey = 'webdav_enabled';
  static const String _webDavBaseUrlKey = 'webdav_base_url';
  static const String _webDavUserIdKey = 'webdav_user_id';
  static const String _webDavUsernameKey = 'webdav_username';
  static const String _webDavPasswordKey = 'webdav_password';

  Future<AppSettings> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String deviceId = prefs.getString(_deviceIdKey) ?? const Uuid().v4();
    await prefs.setString(_deviceIdKey, deviceId);

    return AppSettings(
      deviceId: deviceId,
      titleRefreshDays: prefs.getInt(_titleRefreshDaysKey) ?? 7,
      autoRefreshOnLaunch: prefs.getBool(_autoRefreshOnLaunchKey) ?? true,
      webDavEnabled: prefs.getBool(_webDavEnabledKey) ?? false,
      webDavBaseUrl: prefs.getString(_webDavBaseUrlKey) ?? '',
      webDavUserId: prefs.getString(_webDavUserIdKey) ?? 'default',
      webDavUsername: prefs.getString(_webDavUsernameKey) ?? '',
      webDavPassword: prefs.getString(_webDavPasswordKey) ?? '',
    );
  }

  Future<void> save(AppSettings settings) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceIdKey, settings.deviceId);
    await prefs.setInt(_titleRefreshDaysKey, settings.titleRefreshDays);
    await prefs.setBool(_autoRefreshOnLaunchKey, settings.autoRefreshOnLaunch);
    await prefs.setBool(_webDavEnabledKey, settings.webDavEnabled);
    await prefs.setString(_webDavBaseUrlKey, settings.webDavBaseUrl);
    await prefs.setString(_webDavUserIdKey, settings.webDavUserId);
    await prefs.setString(_webDavUsernameKey, settings.webDavUsername);
    await prefs.setString(_webDavPasswordKey, settings.webDavPassword);
  }
}
