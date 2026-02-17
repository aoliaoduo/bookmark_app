import 'dart:convert';

import 'package:bookmark_app/core/backup/webdav_backup_service.dart';
import 'package:bookmark_app/core/domain/bookmark.dart';
import 'package:bookmark_app/core/sync/webdav_sync_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('uploadSnapshot uses encoded path and unique timestamped names',
      () async {
    final _RecordingHttpClient client = _RecordingHttpClient((
      http.BaseRequest request,
    ) async {
      if (request.method == 'MKCOL') {
        return _response(201);
      }
      if (request.method == 'PUT') {
        return _response(200);
      }
      return _response(404);
    });

    final WebDavBackupService service = WebDavBackupService(
      config: const WebDavConfig(
        baseUrl: 'https://dav.example.com',
        username: 'u',
        password: 'p',
      ),
      client: client,
    );

    await service.uploadSnapshot(
      userId: 'u/1 a',
      bookmarks: <Bookmark>[_bookmark('b-1')],
      timestamp: DateTime.utc(2026, 2, 16, 10, 0, 0),
    );
    await service.uploadSnapshot(
      userId: 'u/1 a',
      bookmarks: <Bookmark>[_bookmark('b-2')],
      timestamp: DateTime.utc(2026, 2, 16, 10, 0, 5),
    );

    final putUrls = client.requests
        .where((http.BaseRequest r) => r.method == 'PUT')
        .map((http.BaseRequest r) => r.url.toString())
        .toList();
    expect(putUrls.length, 2);
    expect(putUrls[0], contains('/BookmarksApp/users/u%2F1%20a/snapshots/'));
    expect(putUrls[1], contains('/BookmarksApp/users/u%2F1%20a/snapshots/'));
    expect(putUrls[0], contains('bookmarks_2026-02-16T10-00-00'));
    expect(putUrls[1], contains('bookmarks_2026-02-16T10-00-05'));
    expect(putUrls[0], isNot(putUrls[1]));
  });

  test('downloadSnapshot encodes snapshot file name', () async {
    final _RecordingHttpClient client = _RecordingHttpClient((
      http.BaseRequest request,
    ) async {
      if (request.method == 'GET') {
        return _response(
          200,
          body: jsonEncode(<String, dynamic>{
            'createdAt': '2026-02-16T10:00:00.000Z',
            'bookmarks': <Map<String, dynamic>>[],
          }),
          headers: <String, String>{'content-type': 'application/json'},
        );
      }
      return _response(404);
    });

    final WebDavBackupService service = WebDavBackupService(
      config: const WebDavConfig(
        baseUrl: 'https://dav.example.com',
        username: 'u',
        password: 'p',
      ),
      client: client,
    );

    await service.downloadSnapshot(
      userId: 'u/1',
      snapshotFileName: 'a/b c.json',
    );

    final http.BaseRequest getRequest = client.requests.firstWhere(
      (http.BaseRequest r) => r.method == 'GET',
    );
    expect(
      getRequest.url.toString(),
      contains('/BookmarksApp/users/u%2F1/snapshots/a%2Fb%20c.json'),
    );
  });

  test('downloadSnapshot validates digest when present', () async {
    final Bookmark bookmark = _bookmark('b-1');
    final _RecordingHttpClient client = _RecordingHttpClient((
      http.BaseRequest request,
    ) async {
      if (request.method == 'GET') {
        return _response(
          200,
          body: jsonEncode(<String, dynamic>{
            'createdAt': '2026-02-16T10:00:00.000Z',
            'bookmarkCount': 1,
            'digestSha256': 'invalid-digest',
            'bookmarks': <Map<String, dynamic>>[
              bookmark.toJson(),
            ],
          }),
          headers: <String, String>{'content-type': 'application/json'},
        );
      }
      return _response(404);
    });

    final WebDavBackupService service = WebDavBackupService(
      config: const WebDavConfig(
        baseUrl: 'https://dav.example.com',
        username: 'u',
        password: 'p',
      ),
      client: client,
    );

    expect(
      () => service.downloadSnapshot(
        userId: 'u/1',
        snapshotFileName: 'a.json',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('downloadSnapshot validates bookmarkCount when present', () async {
    final _RecordingHttpClient client = _RecordingHttpClient((
      http.BaseRequest request,
    ) async {
      if (request.method == 'GET') {
        return _response(
          200,
          body: jsonEncode(<String, dynamic>{
            'createdAt': '2026-02-16T10:00:00.000Z',
            'bookmarkCount': 2,
            'bookmarks': <Map<String, dynamic>>[
              _bookmark('b-1').toJson(),
            ],
          }),
          headers: <String, String>{'content-type': 'application/json'},
        );
      }
      return _response(404);
    });

    final WebDavBackupService service = WebDavBackupService(
      config: const WebDavConfig(
        baseUrl: 'https://dav.example.com',
        username: 'u',
        password: 'p',
      ),
      client: client,
    );

    expect(
      () => service.downloadSnapshot(
        userId: 'u/1',
        snapshotFileName: 'a.json',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('uploadSnapshot with base path avoids duplicated path segments',
      () async {
    final _RecordingHttpClient client = _RecordingHttpClient((
      http.BaseRequest request,
    ) async {
      if (request.method == 'MKCOL') {
        return _response(201);
      }
      if (request.method == 'PUT') {
        return _response(200);
      }
      return _response(404);
    });

    final WebDavBackupService service = WebDavBackupService(
      config: const WebDavConfig(
        baseUrl: 'https://dav.example.com/dav',
        username: 'u',
        password: 'p',
      ),
      client: client,
    );

    await service.uploadSnapshot(
      userId: 'u/1',
      bookmarks: <Bookmark>[_bookmark('b-1')],
      timestamp: DateTime.utc(2026, 2, 16, 10, 0, 0),
    );

    final List<String> urls =
        client.requests.map((http.BaseRequest r) => r.url.toString()).toList();
    for (final String url in urls) {
      expect(url, isNot(contains('/dav/dav/')));
    }
  });
}

class _RecordingHttpClient extends http.BaseClient {
  _RecordingHttpClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      _handler;
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return _handler(request);
  }
}

http.StreamedResponse _response(
  int statusCode, {
  String body = '',
  Map<String, String>? headers,
}) {
  return http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(body)),
    statusCode,
    headers: headers ?? const <String, String>{},
  );
}

Bookmark _bookmark(String id) {
  final DateTime now = DateTime.utc(2026, 2, 16, 10, 0, 0);
  return Bookmark(
    id: id,
    url: 'https://example.com/$id',
    normalizedUrl: 'https://example.com/$id',
    createdAt: now,
    updatedAt: now,
  );
}
