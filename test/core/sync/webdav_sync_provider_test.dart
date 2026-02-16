import 'dart:convert';

import 'package:bookmark_app/core/domain/bookmark.dart';
import 'package:bookmark_app/core/sync/sync_types.dart';
import 'package:bookmark_app/core/sync/webdav_sync_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('pushOps encodes userId/deviceId path segments', () async {
    final _RecordingHttpClient client = _RecordingHttpClient((
      http.BaseRequest request,
    ) async {
      if (request.method == 'MKCOL') {
        return _response(201);
      }
      if (request.method == 'PUT') {
        return _response(201);
      }
      return _response(404);
    });

    final WebDavSyncProvider provider = WebDavSyncProvider(
      config: const WebDavConfig(
        baseUrl: 'https://dav.example.com',
        username: 'u',
        password: 'p',
      ),
      client: client,
    );

    await provider.pushOps(
      userId: 'user/a b',
      deviceId: 'dev#1/2',
      ops: <SyncOp>[
        SyncOp(
          opId: 'op-1',
          type: SyncOpType.upsert,
          bookmark: _bookmark('b-1'),
          occurredAt: DateTime.utc(2026, 2, 16, 11, 0, 0),
          deviceId: 'dev#1/2',
        ),
      ],
    );

    final http.BaseRequest putRequest = client.requests.firstWhere(
      (http.BaseRequest r) => r.method == 'PUT',
    );
    final String url = putRequest.url.toString();
    expect(url, contains('/users/user%2Fa%20b/devices/dev%231%2F2/ops/'));
  });

  test('pullOpsSince uses server last-modified as cursor and includes equals',
      () async {
    final DateTime since = DateTime.utc(2026, 2, 16, 12, 0, 0);
    final String fileModified = 'Mon, 16 Feb 2026 12:00:00 GMT';

    final _RecordingHttpClient client = _RecordingHttpClient((
      http.BaseRequest request,
    ) async {
      final String url = request.url.toString();
      if (request.method == 'PROPFIND') {
        if (url.contains('/devices/devA/ops/')) {
          return _xmlResponse(_opsPropfindXml(fileModified));
        }
        if (url.contains('/devices/devA/')) {
          return _xmlResponse(_devicePropfindXml());
        }
        if (url.contains('/devices/')) {
          return _xmlResponse(_devicesPropfindXml());
        }
      }
      if (request.method == 'GET' &&
          url.contains('/devices/devA/ops/op1.json')) {
        return _jsonResponse(<String, dynamic>{
          'deviceId': 'devA',
          'createdAt': '2020-01-01T00:00:00.000Z',
          'ops': <Map<String, dynamic>>[
            <String, dynamic>{
              'opId': 'op-1',
              'type': 'upsert',
              'bookmark': _bookmark('b-1').toJson(),
              'occurredAt': '2026-02-16T11:30:00.000Z',
              'deviceId': 'devA',
            },
          ],
        });
      }
      return _response(404);
    });

    final WebDavSyncProvider provider = WebDavSyncProvider(
      config: const WebDavConfig(
        baseUrl: 'https://dav.example.com',
        username: 'u',
        password: 'p',
      ),
      client: client,
    );

    final pulled = await provider.pullOpsSince(userId: 'u/1', since: since);
    expect(pulled.length, 1);
    expect(pulled.single.cursorAt, since);
    expect(pulled.single.batch.createdAt, DateTime.utc(2020, 1, 1));
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

http.StreamedResponse _xmlResponse(String xml) {
  return _response(
    207,
    body: xml,
    headers: <String, String>{'content-type': 'application/xml'},
  );
}

http.StreamedResponse _jsonResponse(Map<String, dynamic> json) {
  return _response(
    200,
    body: jsonEncode(json),
    headers: <String, String>{'content-type': 'application/json'},
  );
}

String _devicesPropfindXml() {
  return '''
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/BookmarksApp/users/u%2F1/devices/</d:href>
    <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
  </d:response>
  <d:response>
    <d:href>/BookmarksApp/users/u%2F1/devices/devA/</d:href>
    <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
  </d:response>
</d:multistatus>
''';
}

String _devicePropfindXml() {
  return '''
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/BookmarksApp/users/u%2F1/devices/devA/</d:href>
    <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
  </d:response>
  <d:response>
    <d:href>/BookmarksApp/users/u%2F1/devices/devA/ops/</d:href>
    <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
  </d:response>
</d:multistatus>
''';
}

String _opsPropfindXml(String fileModified) {
  return '''
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/BookmarksApp/users/u%2F1/devices/devA/ops/</d:href>
    <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
  </d:response>
  <d:response>
    <d:href>/BookmarksApp/users/u%2F1/devices/devA/ops/op1.json</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype/>
        <d:getlastmodified>$fileModified</d:getlastmodified>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>
''';
}

Bookmark _bookmark(String id) {
  final DateTime now = DateTime.utc(2026, 2, 16, 11, 0, 0);
  return Bookmark(
    id: id,
    url: 'https://example.com/$id',
    normalizedUrl: 'https://example.com/$id',
    createdAt: now,
    updatedAt: now,
  );
}
