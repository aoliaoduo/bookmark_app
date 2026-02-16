import 'dart:convert';
import 'dart:io';

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
    final String encodedUserId = _encodePathSegment(userId);
    final String encodedDeviceId = _encodePathSegment(deviceId);
    final String opsDir =
        '/BookmarksApp/users/$encodedUserId/devices/$encodedDeviceId/ops';
    final String path = '$opsDir/$ts-$encodedDeviceId.json';

    await _mkcol('/BookmarksApp');
    await _mkcol('/BookmarksApp/users');
    await _mkcol('/BookmarksApp/users/$encodedUserId');
    await _mkcol('/BookmarksApp/users/$encodedUserId/devices');
    await _mkcol('/BookmarksApp/users/$encodedUserId/devices/$encodedDeviceId');
    await _mkcol(opsDir);

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
  Future<List<PulledSyncBatch>> pullOpsSince({
    required String userId,
    required DateTime since,
  }) async {
    final String encodedUserId = _encodePathSegment(userId);
    final List<String> roots = <String>[
      '/BookmarksApp/users/$encodedUserId/devices/',
      '/BookmarksApp/ussers/$encodedUserId/devices/',
    ];
    final List<_DavEntry> files = <_DavEntry>[];
    final Set<String> seenFilePaths = <String>{};
    for (final String root in roots) {
      final List<_DavEntry> listed = await _listJsonFilesRecursively(root);
      for (final _DavEntry entry in listed) {
        if (seenFilePaths.add(_normalizePath(entry.path))) {
          files.add(entry);
        }
      }
    }
    final List<PulledSyncBatch> result = <PulledSyncBatch>[];

    for (final _DavEntry file in files) {
      final String relativePath = file.path;
      if (!relativePath.contains('/ops/')) continue;
      final DateTime? lastModified = file.lastModified;
      if (lastModified != null && lastModified.isBefore(since)) {
        continue;
      }

      final Uri uri = Uri.parse('${_config.baseUrl}$relativePath');
      final http.Response response = await _client.get(
        uri,
        headers: _headers(),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final Map<String, dynamic> json =
            jsonDecode(response.body) as Map<String, dynamic>;
        final SyncBatch batch = SyncBatch.fromJson(json);
        result.add(
          PulledSyncBatch(
            batch: batch,
            cursorAt: lastModified ?? batch.createdAt,
          ),
        );
      }
    }

    result.sort(
      (PulledSyncBatch a, PulledSyncBatch b) {
        final int cursorCompare = a.cursorAt.compareTo(b.cursorAt);
        if (cursorCompare != 0) return cursorCompare;
        return a.batch.createdAt.compareTo(b.batch.createdAt);
      },
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

  Future<List<_DavEntry>> _listJsonFilesRecursively(String rootPath) async {
    final String normalizedRoot = _normalizePath(rootPath);
    final List<_DavEntry> files = <_DavEntry>[];
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
          files.add(entry);
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
        '<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getlastmodified/></d:prop></d:propfind>';

    final http.StreamedResponse streamed = await _client.send(request);
    final http.Response response = await http.Response.fromStream(streamed);

    if (!(response.statusCode == 207 ||
        (response.statusCode >= 200 && response.statusCode < 300))) {
      if (response.statusCode == 404 || response.statusCode == 409) {
        return <_DavEntry>[];
      }
      throw Exception('PROPFIND failed: ${response.statusCode} for $path');
    }

    final XmlDocument doc = XmlDocument.parse(response.body);
    final List<_DavEntry> entries = <_DavEntry>[];

    for (final XmlElement element in _findAllByLocalName(doc, 'response')) {
      XmlElement? hrefNode;
      for (final XmlElement node in _findAllByLocalName(element, 'href')) {
        hrefNode = node;
        break;
      }
      if (hrefNode == null) continue;
      final String hrefRaw = hrefNode.innerText.trim();
      if (hrefRaw.isEmpty) continue;

      final String pathValue = _pathFromHref(hrefRaw);
      bool isCollection = false;
      for (final XmlElement rt
          in _findAllByLocalName(element, 'resourcetype')) {
        if (_findAllByLocalName(rt, 'collection').isNotEmpty) {
          isCollection = true;
          break;
        }
      }

      DateTime? lastModified;
      XmlElement? modifiedNode;
      for (final XmlElement node
          in _findAllByLocalName(element, 'getlastmodified')) {
        modifiedNode = node;
        break;
      }
      if (modifiedNode != null) {
        final String raw = modifiedNode.innerText.trim();
        if (raw.isNotEmpty) {
          try {
            lastModified = HttpDate.parse(raw).toUtc();
          } catch (_) {
            lastModified = DateTime.tryParse(raw)?.toUtc();
          }
        }
      }

      entries.add(
        _DavEntry(
          path: pathValue,
          isCollection: isCollection,
          lastModified: lastModified,
        ),
      );
    }

    return entries;
  }

  String _pathFromHref(String href) {
    final Uri? uri = Uri.tryParse(href);
    if (uri != null && uri.hasAuthority) {
      return _normalizePath(uri.path);
    }
    return _normalizePath(href);
  }

  bool _samePath(String a, String b) {
    return _normalizePath(a).replaceFirst(RegExp(r'/+$'), '') ==
        _normalizePath(b).replaceFirst(RegExp(r'/+$'), '');
  }

  String _normalizePath(String path) {
    final String withLeading = path.startsWith('/') ? path : '/$path';
    return withLeading.replaceAll(RegExp(r'/{2,}'), '/');
  }

  Iterable<XmlElement> _findAllByLocalName(XmlNode node, String localName) {
    return node.descendants
        .whereType<XmlElement>()
        .where((XmlElement element) => element.name.local == localName);
  }

  String _encodePathSegment(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('WebDAV path segment cannot be empty');
    }
    return Uri.encodeComponent(trimmed);
  }
}

class _DavEntry {
  const _DavEntry({
    required this.path,
    required this.isCollection,
    this.lastModified,
  });

  final String path;
  final bool isCollection;
  final DateTime? lastModified;
}
