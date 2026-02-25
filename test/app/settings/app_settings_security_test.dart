import 'package:bookmark_app/app/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('syncReady requires HTTPS WebDAV base URL', () {
    final AppSettings insecure = AppSettings(
      deviceId: 'd1',
      titleRefreshDays: 7,
      autoRefreshOnLaunch: true,
      autoSyncOnLaunch: true,
      autoSyncOnChange: true,
      webDavEnabled: true,
      webDavBaseUrl: 'http://dav.example.com',
      webDavUserId: 'u1',
      webDavUsername: 'name',
      webDavPassword: 'secret',
    );
    final AppSettings secure = insecure.copyWith(
      webDavBaseUrl: 'https://dav.example.com',
    );

    expect(insecure.webDavUsesHttps, isFalse);
    expect(insecure.syncReady, isFalse);
    expect(secure.webDavUsesHttps, isTrue);
    expect(secure.syncReady, isTrue);
  });

  test('isSecureWebDavBaseUrl rejects invalid and non-https values', () {
    expect(AppSettings.isSecureWebDavBaseUrl(''), isFalse);
    expect(AppSettings.isSecureWebDavBaseUrl('not a url'), isFalse);
    expect(
        AppSettings.isSecureWebDavBaseUrl('http://dav.example.com'), isFalse);
    expect(AppSettings.isSecureWebDavBaseUrl('https://'), isFalse);
    expect(
        AppSettings.isSecureWebDavBaseUrl('https://dav.example.com'), isTrue);
  });
}
