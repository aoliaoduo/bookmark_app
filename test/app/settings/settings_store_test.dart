import 'package:bookmark_app/app/settings/app_settings.dart';
import 'package:bookmark_app/app/settings/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('load migrates legacy password from SharedPreferences', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'webdav_password': 'legacy-secret',
      'webdav_enabled': true,
      'webdav_base_url': 'https://dav.example.com',
      'webdav_user_id': 'u1',
      'webdav_username': 'name',
    });
    final _InMemorySecretStore secretStore = _InMemorySecretStore();
    final SettingsStore store = SettingsStore(secretStore: secretStore);

    final AppSettings settings = await store.load();

    expect(
      settings.webDavPassword,
      AppSettings.securePasswordPlaceholder,
    );
    expect(settings.usesSecurePasswordPlaceholder, isTrue);
    expect(await store.loadWebDavPassword(), 'legacy-secret');
    expect(settings.themePreference, AppThemePreference.system);
    expect(settings.homeSortPreference, HomeSortPreference.updatedDesc);
    expect(secretStore.readSync('webdav_password'), 'legacy-secret');
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('webdav_password'), isNull);
  });

  test('save writes password to secret store instead of preferences', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final _InMemorySecretStore secretStore = _InMemorySecretStore();
    final SettingsStore store = SettingsStore(secretStore: secretStore);
    final AppSettings settings = AppSettings(
      deviceId: 'd1',
      titleRefreshDays: 7,
      autoRefreshOnLaunch: true,
      autoSyncOnLaunch: true,
      autoSyncOnChange: true,
      themePreference: AppThemePreference.dark,
      homeSortPreference: HomeSortPreference.urlAsc,
      webDavEnabled: true,
      webDavBaseUrl: 'https://dav.example.com',
      webDavUserId: 'u1',
      webDavUsername: 'name',
      webDavPassword: 'secret-1',
    );

    await store.save(settings);

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('webdav_password'), isNull);
    expect(prefs.getString('theme_preference'), 'dark');
    expect(prefs.getString('home_sort_preference'), 'urlAsc');
    expect(secretStore.readSync('webdav_password'), 'secret-1');

    await store.save(
      settings.copyWith(
        webDavPassword: AppSettings.securePasswordPlaceholder,
      ),
    );
    expect(secretStore.readSync('webdav_password'), 'secret-1');

    await store.save(settings.copyWith(webDavPassword: ''));
    expect(secretStore.readSync('webdav_password'), isNull);
  });

  test('clearAll removes preferences and secret password', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'device_id': 'd1',
      'title_refresh_days': 5,
      'auto_refresh_on_launch': false,
      'auto_sync_on_launch': false,
      'auto_sync_on_change': false,
      'theme_preference': 'dark',
      'home_sort_preference': 'createdDesc',
      'webdav_enabled': true,
      'webdav_base_url': 'https://dav.example.com',
      'webdav_user_id': 'u1',
      'webdav_username': 'name',
      'webdav_password': 'legacy-secret',
    });
    final _InMemorySecretStore secretStore = _InMemorySecretStore();
    await secretStore.write(key: 'webdav_password', value: 'secure-secret');
    final SettingsStore store = SettingsStore(secretStore: secretStore);

    await store.clearAll();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('device_id'), isNull);
    expect(prefs.getInt('title_refresh_days'), isNull);
    expect(prefs.getBool('auto_refresh_on_launch'), isNull);
    expect(prefs.getBool('auto_sync_on_launch'), isNull);
    expect(prefs.getBool('auto_sync_on_change'), isNull);
    expect(prefs.getString('theme_preference'), isNull);
    expect(prefs.getString('home_sort_preference'), isNull);
    expect(prefs.getBool('webdav_enabled'), isNull);
    expect(prefs.getString('webdav_base_url'), isNull);
    expect(prefs.getString('webdav_user_id'), isNull);
    expect(prefs.getString('webdav_username'), isNull);
    expect(prefs.getString('webdav_password'), isNull);
    expect(secretStore.readSync('webdav_password'), isNull);
  });
}

class _InMemorySecretStore implements SecretStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async {
    return _values[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }

  String? readSync(String key) => _values[key];
}
