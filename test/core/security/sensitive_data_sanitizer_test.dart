import 'package:bookmark_app/core/security/sensitive_data_sanitizer.dart';
import 'package:bookmark_app/core/sync/webdav_sync_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sanitizeText masks basic auth token and key-value secrets', () {
    const String raw =
        'Authorization: Basic dXNlcjpwYXNz password=abc123 token:xyz';

    final String sanitized = SensitiveDataSanitizer.sanitizeText(raw);

    expect(sanitized, isNot(contains('dXNlcjpwYXNz')));
    expect(sanitized, isNot(contains('abc123')));
    expect(sanitized, isNot(contains('xyz')));
    expect(sanitized, contains('Basic ***'));
    expect(sanitized, contains('password=***'));
    expect(sanitized, contains('token:***'));
  });

  test('sanitizeText masks url userinfo and sensitive query params', () {
    const String raw =
        'failed at https://alice:secret@dav.example.com/path?token=abc&foo=1&password=xyz';

    final String sanitized = SensitiveDataSanitizer.sanitizeText(raw);

    expect(sanitized, isNot(contains('alice:secret')));
    expect(sanitized, isNot(contains('token=abc')));
    expect(sanitized, isNot(contains('password=xyz')));
    expect(sanitized, contains('https://***@dav.example.com/path?'));
    expect(sanitized, contains('token=***'));
    expect(sanitized, contains('password=***'));
    expect(sanitized, contains('foo=1'));
  });

  test('WebDavRequestException toString is sanitized', () {
    final WebDavRequestException error = WebDavRequestException(
      'sync failed',
      path: '/BookmarksApp/users/u?token=abc',
      responseBody:
          '{"authorization":"Basic dXNlcjpwYXNz","password":"abc123"}',
      cause: const FormatException('username=alice'),
    );

    final String text = error.toString();

    expect(text, isNot(contains('token=abc')));
    expect(text, isNot(contains('dXNlcjpwYXNz')));
    expect(text, isNot(contains('abc123')));
    expect(text, isNot(contains('alice')));
    expect(text, contains('token=***'));
    expect(text, contains('"authorization":"***"'));
    expect(text, contains('"password":"***"'));
    expect(text, contains('username=***'));
  });
}
