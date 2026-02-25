import 'package:bookmark_app/app/sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizeWebDavBaseUrl trims trailing BookmarksApp segment', () {
    expect(
      normalizeWebDavBaseUrl(
        'https://dav.example.com/remote.php/dav/files/user/BookmarksApp',
      ),
      'https://dav.example.com/remote.php/dav/files/user',
    );
  });

  test('normalizeWebDavBaseUrl trims BookmarksApp/users tree safely', () {
    expect(
      normalizeWebDavBaseUrl(
        'https://dav.example.com/remote.php/dav/files/user/BookmarksApp/users/u1/devices/d1',
      ),
      'https://dav.example.com/remote.php/dav/files/user',
    );
  });

  test('normalizeWebDavBaseUrl does not trim similar segment names', () {
    expect(
      normalizeWebDavBaseUrl(
        'https://dav.example.com/remote.php/dav/files/user/bookmarksapplication/users/u1',
      ),
      'https://dav.example.com/remote.php/dav/files/user/bookmarksapplication/users/u1',
    );
  });

  test('normalizeWebDavBaseUrl does not trim unrelated descendants', () {
    expect(
      normalizeWebDavBaseUrl(
        'https://dav.example.com/remote.php/dav/files/user/BookmarksApp/archive',
      ),
      'https://dav.example.com/remote.php/dav/files/user/BookmarksApp/archive',
    );
  });

  test('normalizeWebDavBaseUrl clears query and fragment', () {
    expect(
      normalizeWebDavBaseUrl(
        'https://dav.example.com/dav/BookmarksApp?token=123#frag',
      ),
      'https://dav.example.com/dav',
    );
  });
}
