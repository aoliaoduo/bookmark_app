import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'app_settings.dart';

abstract class SecretStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

class FlutterSecretStore implements SecretStore {
  FlutterSecretStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) {
    return _storage.read(key: key);
  }

  @override
  Future<void> write({required String key, required String value}) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete({required String key}) {
    return _storage.delete(key: key);
  }
}

class SettingsStore {
  SettingsStore({SecretStore? secretStore})
      : _secretStore = secretStore ?? FlutterSecretStore();

  static const String _deviceIdKey = 'device_id';
  static const String _titleRefreshDaysKey = 'title_refresh_days';
  static const String _autoRefreshOnLaunchKey = 'auto_refresh_on_launch';
  static const String _autoSyncOnLaunchKey = 'auto_sync_on_launch';
  static const String _autoSyncOnChangeKey = 'auto_sync_on_change';
  static const String _themePreferenceKey = 'theme_preference';
  static const String _homeSortPreferenceKey = 'home_sort_preference';
  static const String _webDavEnabledKey = 'webdav_enabled';
  static const String _webDavBaseUrlKey = 'webdav_base_url';
  static const String _webDavUserIdKey = 'webdav_user_id';
  static const String _webDavUsernameKey = 'webdav_username';
  static const String _webDavPasswordKey = 'webdav_password';
  final SecretStore _secretStore;

  Future<AppSettings> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String deviceId = prefs.getString(_deviceIdKey) ?? const Uuid().v4();
    await prefs.setString(_deviceIdKey, deviceId);
    final String password = await _loadPassword(prefs);
    final String runtimePassword =
        password.isEmpty ? '' : AppSettings.securePasswordPlaceholder;

    return AppSettings(
      deviceId: deviceId,
      titleRefreshDays: prefs.getInt(_titleRefreshDaysKey) ?? 7,
      autoRefreshOnLaunch: prefs.getBool(_autoRefreshOnLaunchKey) ?? true,
      autoSyncOnLaunch: prefs.getBool(_autoSyncOnLaunchKey) ?? true,
      autoSyncOnChange: prefs.getBool(_autoSyncOnChangeKey) ?? true,
      themePreference: AppThemePreference.fromStorage(
        prefs.getString(_themePreferenceKey),
      ),
      homeSortPreference: HomeSortPreference.fromStorage(
        prefs.getString(_homeSortPreferenceKey),
      ),
      webDavEnabled: prefs.getBool(_webDavEnabledKey) ?? false,
      webDavBaseUrl: prefs.getString(_webDavBaseUrlKey) ?? '',
      webDavUserId: prefs.getString(_webDavUserIdKey) ?? 'default',
      webDavUsername: prefs.getString(_webDavUsernameKey) ?? '',
      webDavPassword: runtimePassword,
    );
  }

  Future<void> save(AppSettings settings) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceIdKey, settings.deviceId);
    await prefs.setInt(_titleRefreshDaysKey, settings.titleRefreshDays);
    await prefs.setBool(_autoRefreshOnLaunchKey, settings.autoRefreshOnLaunch);
    await prefs.setBool(_autoSyncOnLaunchKey, settings.autoSyncOnLaunch);
    await prefs.setBool(_autoSyncOnChangeKey, settings.autoSyncOnChange);
    await prefs.setString(_themePreferenceKey, settings.themePreference.name);
    await prefs.setString(
      _homeSortPreferenceKey,
      settings.homeSortPreference.name,
    );
    await prefs.setBool(_webDavEnabledKey, settings.webDavEnabled);
    await prefs.setString(_webDavBaseUrlKey, settings.webDavBaseUrl);
    await prefs.setString(_webDavUserIdKey, settings.webDavUserId);
    await prefs.setString(_webDavUsernameKey, settings.webDavUsername);
    if (settings.usesSecurePasswordPlaceholder) {
      final String? existing = await _secretStore.read(key: _webDavPasswordKey);
      if (existing == null || existing.isEmpty) {
        await _savePassword('');
      }
    } else {
      await _savePassword(settings.webDavPassword);
    }
    await prefs.remove(_webDavPasswordKey);
  }

  Future<String> loadWebDavPassword() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return _loadPassword(prefs);
  }

  Future<void> clearAll() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deviceIdKey);
    await prefs.remove(_titleRefreshDaysKey);
    await prefs.remove(_autoRefreshOnLaunchKey);
    await prefs.remove(_autoSyncOnLaunchKey);
    await prefs.remove(_autoSyncOnChangeKey);
    await prefs.remove(_themePreferenceKey);
    await prefs.remove(_homeSortPreferenceKey);
    await prefs.remove(_webDavEnabledKey);
    await prefs.remove(_webDavBaseUrlKey);
    await prefs.remove(_webDavUserIdKey);
    await prefs.remove(_webDavUsernameKey);
    await prefs.remove(_webDavPasswordKey);
    await _secretStore.delete(key: _webDavPasswordKey);
  }

  Future<String> _loadPassword(SharedPreferences prefs) async {
    final String? secure = await _secretStore.read(key: _webDavPasswordKey);
    if (secure != null && secure.isNotEmpty) {
      return secure;
    }

    final String? legacy = prefs.getString(_webDavPasswordKey);
    if (legacy == null || legacy.isEmpty) {
      return '';
    }

    await _secretStore.write(key: _webDavPasswordKey, value: legacy);
    await prefs.remove(_webDavPasswordKey);
    return legacy;
  }

  Future<void> _savePassword(String value) async {
    if (value.isEmpty) {
      await _secretStore.delete(key: _webDavPasswordKey);
      return;
    }
    await _secretStore.write(key: _webDavPasswordKey, value: value);
  }
}
