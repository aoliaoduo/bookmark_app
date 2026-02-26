import 'dart:convert';

import 'package:http/http.dart' as http;

import '../remote/sync_remote.dart';
import '../sync_engine.dart';
import '../sync_models.dart';
import 'webdav_config.dart';

class WebDavRemote implements SyncRemote {
  WebDavRemote({required this.config, http.Client? client})
    : _client = client ?? http.Client() {
    _baseUri = Uri.parse(_normalizeBaseUrl(config.baseUrl));
  }

  final WebDavConfig config;
  final http.Client _client;
  late final Uri _baseUri;

  static const String _propfindBody = '''<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:"><d:allprop/></d:propfind>''';

  @override
  Future<void> ensureInitialized({required String deviceId}) async {
    final List<String> dirs = <String>[
      'meta',
      'meta/clients',
      'objects',
      'objects/todo',
      'objects/note',
      'objects/bookmark',
      'objects/tag',
      'objects/secret',
      'changes',
      'changes/$deviceId',
      'changes/$deviceId/${_datePart(DateTime.now())}',
    ];
    for (final String path in dirs) {
      await _ensureDirectory(path);
    }
  }

  @override
  Future<List<SyncChange>> pullChanges({
    required String currentDeviceId,
    required int limit,
    String? afterChangeId,
  }) async {
    final List<_WebDavEntry> deviceDirs = await _listDirectory('changes');
    final List<String> devices =
        deviceDirs
            .where((e) => e.isCollection)
            .map((e) => _basename(e.path))
            .where((String id) => id.isNotEmpty && id != currentDeviceId)
            .toList(growable: false)
          ..sort();

    final List<SyncChange> collected = <SyncChange>[];
    for (final String deviceId in devices.reversed) {
      if (collected.length >= limit) {
        break;
      }
      final List<_WebDavEntry> dateDirs = await _listDirectory(
        'changes/$deviceId',
      );
      final List<String> dates =
          dateDirs
              .where((e) => e.isCollection)
              .map((e) => _basename(e.path))
              .where((String s) => s.isNotEmpty)
              .toList(growable: false)
            ..sort();

      for (final String date in dates.reversed) {
        if (collected.length >= limit) {
          break;
        }
        final List<_WebDavEntry> changeFiles = await _listDirectory(
          'changes/$deviceId/$date',
        );
        final List<_WebDavEntry> files =
            changeFiles
                .where((e) => !e.isCollection && e.path.endsWith('.json'))
                .toList(growable: false)
              ..sort((a, b) => a.path.compareTo(b.path));
        for (final _WebDavEntry file in files) {
          if (collected.length >= limit) {
            break;
          }
          final String raw = await _getText(file.path);
          final Object? decoded = jsonDecode(raw);
          if (decoded is! Map<String, Object?>) {
            continue;
          }
          collected.add(SyncChange.fromJson(decoded));
        }
      }
    }

    collected.sort((SyncChange a, SyncChange b) {
      final int byCreated = a.createdAt.compareTo(b.createdAt);
      if (byCreated != 0) {
        return byCreated;
      }
      return a.id.compareTo(b.id);
    });

    if (afterChangeId == null) {
      return collected.take(limit).toList(growable: false);
    }
    int start =
        collected.indexWhere((SyncChange c) => c.id == afterChangeId) + 1;
    if (start < 0) {
      start = 0;
    }
    return collected.skip(start).take(limit).toList(growable: false);
  }

  @override
  Future<SyncObject?> getObject({
    required String entityType,
    required String entityId,
  }) async {
    final String path = 'objects/$entityType/$entityId.json';
    final _WebDavResponse response = await _request(
      method: 'GET',
      path: path,
      acceptedStatus: const <int>{200, 404},
    );
    if (response.statusCode == 404) {
      return null;
    }
    return SyncObject.fromJsonString(response.body);
  }

  @override
  Future<void> putObject(SyncObject object) async {
    await _ensureDirectory('objects/${object.entityType}');
    await _request(
      method: 'PUT',
      path: 'objects/${object.entityType}/${object.entityId}.json',
      body: object.toJsonString(),
      acceptedStatus: const <int>{200, 201, 204},
    );
  }

  @override
  Future<void> putChange(SyncChange change) async {
    final DateTime date = DateTime.fromMillisecondsSinceEpoch(
      change.createdAt,
    ).toLocal();
    final String datePath = _datePart(date);
    await _ensureDirectory('changes/${change.deviceId}/$datePath');
    await _request(
      method: 'PUT',
      path: 'changes/${change.deviceId}/$datePath/${change.id}.json',
      body: jsonEncode(change.toJson()),
      acceptedStatus: const <int>{200, 201, 204},
    );
  }

  @override
  Future<void> updateClientMeta({
    required String deviceId,
    required int lastSeenLamport,
    String? lastAppliedChangeId,
  }) async {
    await _ensureDirectory('meta/clients');
    await _request(
      method: 'PUT',
      path: 'meta/clients/$deviceId.json',
      body: jsonEncode(<String, Object?>{
        'device_id': deviceId,
        'last_seen_lamport': lastSeenLamport,
        'last_applied_change_id': lastAppliedChangeId,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }),
      acceptedStatus: const <int>{200, 201, 204},
    );
  }

  Future<void> _ensureDirectory(String path) async {
    final List<String> parts = path
        .split('/')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    String current = '';
    for (final String part in parts) {
      current = current.isEmpty ? part : '$current/$part';
      await _request(
        method: 'MKCOL',
        path: current,
        acceptedStatus: const <int>{201, 301, 405, 409},
      );
    }
  }

  Future<List<_WebDavEntry>> _listDirectory(String path) async {
    final _WebDavResponse response = await _request(
      method: 'PROPFIND',
      path: path,
      headers: const <String, String>{'Depth': '1'},
      body: _propfindBody,
      acceptedStatus: const <int>{207, 404},
    );
    if (response.statusCode == 404) {
      return const <_WebDavEntry>[];
    }
    return _parsePropfindResponse(path, response.body);
  }

  List<_WebDavEntry> _parsePropfindResponse(String targetPath, String body) {
    final List<_WebDavEntry> entries = <_WebDavEntry>[];
    final RegExp responseExp = RegExp(
      r'<[^>]*response[^>]*>([\s\S]*?)</[^>]*response>',
      caseSensitive: false,
    );
    final RegExp hrefExp = RegExp(
      r'<[^>]*href[^>]*>([\s\S]*?)</[^>]*href>',
      caseSensitive: false,
    );
    final RegExp collectionExp = RegExp(
      r'<[^>]*collection\s*/>',
      caseSensitive: false,
    );
    final String normalizedTarget = _normalizePath(targetPath);

    for (final RegExpMatch match in responseExp.allMatches(body)) {
      final String block = match.group(1) ?? '';
      final RegExpMatch? hrefMatch = hrefExp.firstMatch(block);
      if (hrefMatch == null) {
        continue;
      }
      final String href = hrefMatch.group(1)?.trim() ?? '';
      final String relativePath = _hrefToRelativePath(href);
      if (relativePath.isEmpty || relativePath == normalizedTarget) {
        continue;
      }
      entries.add(
        _WebDavEntry(
          path: relativePath,
          isCollection: collectionExp.hasMatch(block),
        ),
      );
    }
    return entries;
  }

  String _hrefToRelativePath(String href) {
    final Uri uri = Uri.parse(href);
    final String path = Uri.decodeComponent(uri.path);
    final String basePath = _baseUri.path.endsWith('/')
        ? _baseUri.path
        : '${_baseUri.path}/';
    String relative = path;
    if (relative.startsWith(basePath)) {
      relative = relative.substring(basePath.length);
    } else if (relative.startsWith('/')) {
      relative = relative.substring(1);
    }
    return _normalizePath(relative);
  }

  String _normalizePath(String path) {
    String normalized = path.trim();
    normalized = normalized.replaceAll('\\', '/');
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  String _basename(String path) {
    final String normalized = _normalizePath(path);
    if (normalized.isEmpty) {
      return '';
    }
    final int idx = normalized.lastIndexOf('/');
    return idx >= 0 ? normalized.substring(idx + 1) : normalized;
  }

  String _datePart(DateTime dateTime) {
    final int y = dateTime.year;
    final int m = dateTime.month;
    final int d = dateTime.day;
    return '$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
  }

  String _normalizeBaseUrl(String raw) {
    String url = raw.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return '$url/';
  }

  Future<String> _getText(String path) async {
    final _WebDavResponse response = await _request(
      method: 'GET',
      path: path,
      acceptedStatus: const <int>{200},
    );
    return response.body;
  }

  Future<_WebDavResponse> _request({
    required String method,
    required String path,
    Set<int> acceptedStatus = const <int>{200},
    Map<String, String>? headers,
    String? body,
  }) async {
    final Uri uri = _baseUri.resolve(_normalizePath(path));
    final String defaultContentType = method == 'PROPFIND'
        ? 'application/xml; charset=utf-8'
        : 'application/json; charset=utf-8';
    final http.Request request = http.Request(method, uri);
    request.headers.addAll(<String, String>{
      'Authorization': _buildAuthHeader(),
      'Content-Type': defaultContentType,
      ...?headers,
    });
    if (body != null) {
      request.body = body;
    }
    final http.StreamedResponse streamed = await _client.send(request);
    final http.Response response = await http.Response.fromStream(streamed);
    if (!acceptedStatus.contains(response.statusCode)) {
      throw SyncRemoteException(
        message:
            'WebDAV $method ${uri.path} 失败: ${response.statusCode} ${response.body}',
        statusCode: response.statusCode,
      );
    }
    return _WebDavResponse(
      statusCode: response.statusCode,
      body: response.body,
      headers: response.headers,
    );
  }

  String _buildAuthHeader() {
    final String token = base64Encode(
      utf8.encode('${config.username}:${config.appPassword}'),
    );
    return 'Basic $token';
  }
}

class _WebDavResponse {
  const _WebDavResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

class _WebDavEntry {
  const _WebDavEntry({required this.path, required this.isCollection});

  final String path;
  final bool isCollection;
}
