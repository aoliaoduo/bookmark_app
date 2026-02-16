import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'sync_provider.dart';
import 'sync_types.dart';

class WebDavConfig {
  const WebDavConfig({
    required this.baseUrl,
    required this.username,
    required this.password,
  });

  final String baseUrl;
  final String username;
  final String password;
}

class WebDavSyncProvider implements SyncProvider {
  WebDavSyncProvider({required WebDavConfig config, http.Client? client})
    : _config = config,
      _client = client ?? http.Client();

  final WebDavConfig _config;
  final http.Client _client;

  @override
  Future<void> pushOps({
    required String userId,
    required String deviceId,
    required List<SyncOp> ops,
  }) async {
    if (ops.isEmpty) return;

    final DateTime now = DateTime.now().toUtc();
    final SyncBatch batch = SyncBatch(
      deviceId: deviceId,
      createdAt: now,
      ops: ops,
    );

    final String ts = now.toIso8601String().replaceAll(':', '-');
    final String path =
        '/BookmarksApp/users/$userId/devices/$deviceId/ops/$ts-$deviceId.json';

    await _mkcol('/BookmarksApp');
    await _mkcol('/BookmarksApp/users');
    await _mkcol('/BookmarksApp/users/$userId');
    await _mkcol('/BookmarksApp/users/$userId/devices');
    await _mkcol('/BookmarksApp/users/$userId/devices/$deviceId');
    await _mkcol('/BookmarksApp/users/$userId/devices/$deviceId/ops');

    final Uri uri = Uri.parse('${_config.baseUrl}$path');
    final http.Response response = await _client.put(
      uri,
      headers: _headers(contentType: 'application/json'),
      body: jsonEncode(batch.toJson()),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'WebDAV push failed: ${response.statusCode} ${response.body}',
      );
    }
  }

  @override
  Future<List<SyncBatch>> pullOpsSince({
    required String userId,
    required DateTime since,
  }) async {
    final String root = '/BookmarksApp/users/$userId/devices/';
    final List<String> files = await _listJsonFilesRecursively(root);
    final List<SyncBatch> result = <SyncBatch>[];

    for (final String relativePath in files) {
      if (!relativePath.contains('/ops/')) continue;
      final Uri uri = Uri.parse('${_config.baseUrl}$relativePath');
      final http.Response response = await _client.get(
        uri,
        headers: _headers(),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final Map<String, dynamic> json =
            jsonDecode(response.body) as Map<String, dynamic>;
        final SyncBatch batch = SyncBatch.fromJson(json);
        if (batch.createdAt.isAfter(since)) {
          result.add(batch);
        }
      }
    }

    result.sort(
      (SyncBatch a, SyncBatch b) => a.createdAt.compareTo(b.createdAt),
    );
    return result;
  }

  Map<String, String> _headers({String? contentType}) {
    final String basic = base64Encode(
      utf8.encode('${_config.username}:${_config.password}'),
    );
    return <String, String>{
      'Authorization': 'Basic $basic',
      if (contentType != null) 'Content-Type': contentType,
    };
  }

  Future<void> _mkcol(String path) async {
    final Uri uri = Uri.parse('${_config.baseUrl}$path');
    final http.Request request = http.Request('MKCOL', uri);
    request.headers.addAll(_headers());
    final http.StreamedResponse response = await _client.send(request);
    if (!(response.statusCode == 201 || response.statusCode == 405)) {
      throw Exception('MKCOL failed for $path with ${response.statusCode}');
    }
  }

  Future<List<String>> _listJsonFilesRecursively(String rootPath) async {
    final String normalizedRoot = _normalizePath(rootPath);
    final List<String> files = <String>[];
    final Set<String> visited = <String>{};
    final List<String> pending = <String>[normalizedRoot];

    while (pending.isNotEmpty) {
      final String current = pending.removeLast();
      if (!visited.add(current)) {
        continue;
      }

      final List<_DavEntry> entries = await _propfind(current);
      for (final _DavEntry entry in entries) {
        if (_samePath(entry.path, current)) continue;

        if (entry.isCollection) {
          pending.add(entry.path);
        } else if (entry.path.toLowerCase().endsWith('.json')) {
          files.add(entry.path);
        }
      }
    }

    return files;
  }

  Future<List<_DavEntry>> _propfind(String path) async {
    final Uri uri = Uri.parse('${_config.baseUrl}${_normalizePath(path)}');
    final http.Request request = http.Request('PROPFIND', uri);
    request.headers.addAll(
      _headers(contentType: 'application/xml')
        ..addAll(<String, String>{'Depth': '1'}),
    );
    request.body =
        '<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>';

    final http.StreamedResponse streamed = await _client.send(request);
    final http.Response response = await http.Response.fromStream(streamed);

    if (!(response.statusCode == 207 ||
        (response.statusCode >= 200 && response.statusCode < 300))) {
      if (response.statusCode == 404) {
        return <_DavEntry>[];
      }
      throw Exception('PROPFIND failed: ${response.statusCode} for $path');
    }

    final XmlDocument doc = XmlDocument.parse(response.body);
    final List<_DavEntry> entries = <_DavEntry>[];

    for (final XmlElement element in doc.findAllElements('response')) {
      XmlElement? hrefNode;
      for (final XmlElement node in element.findAllElements('href')) {
        hrefNode = node;
        break;
      }
      if (hrefNode == null) continue;
      final String hrefRaw = hrefNode.innerText.trim();
      if (hrefRaw.isEmpty) continue;

      final String pathValue = _pathFromHref(hrefRaw);
      bool isCollection = false;
      for (final XmlElement rt in element.findAllElements('resourcetype')) {
        if (rt.findAllElements('collection').isNotEmpty) {
          isCollection = true;
          break;
        }
      }

      entries.add(_DavEntry(path: pathValue, isCollection: isCollection));
    }

    return entries;
  }

  String _pathFromHref(String href) {
    final String decoded = Uri.decodeFull(href);
    final Uri? uri = Uri.tryParse(decoded);
    if (uri != null && uri.hasAuthority) {
      return _normalizePath(uri.path);
    }
    return _normalizePath(decoded);
  }

  bool _samePath(String a, String b) {
    return _normalizePath(a).replaceFirst(RegExp(r'/+$'), '') ==
        _normalizePath(b).replaceFirst(RegExp(r'/+$'), '');
  }

  String _normalizePath(String path) {
    final String withLeading = path.startsWith('/') ? path : '/$path';
    return withLeading.replaceAll(RegExp(r'/{2,}'), '/');
  }
}

class _DavEntry {
  const _DavEntry({required this.path, required this.isCollection});

  final String path;
  final bool isCollection;
}
