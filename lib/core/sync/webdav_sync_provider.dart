import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:charset/charset.dart';
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
  WebDavSyncProvider({
    required WebDavConfig config,
    http.Client? client,
    Duration requestTimeout = const Duration(seconds: 25),
  })  : _config = config,
        _client = client ?? http.Client(),
        _ownsClient = client == null,
        _baseUri = _parseBaseUri(config.baseUrl),
        _requestTimeout = requestTimeout;

  final WebDavConfig _config;
  final http.Client _client;
  final bool _ownsClient;
  final Uri _baseUri;
  final Duration _requestTimeout;

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

    final Uri uri = _buildUri(path);
    final http.Response response;
    try {
      response = await _client
          .put(
            uri,
            headers: _headers(contentType: 'application/json'),
            body: jsonEncode(batch.toJson()),
          )
          .timeout(_requestTimeout);
    } on TimeoutException catch (e) {
      throw WebDavRequestException(
        'WebDAV push request timed out',
        path: path,
        cause: e,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WebDavRequestException(
        'WebDAV push failed',
        statusCode: response.statusCode,
        path: path,
        responseBody: _decodeResponseBody(response),
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
      final List<_DavEntry> listed = await _listOpsJsonFilesForDevicesRoot(
        root,
      );
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

      final Uri uri = _buildUri(relativePath);
      final http.Response response;
      try {
        response = await _client
            .get(uri, headers: _headers())
            .timeout(_requestTimeout);
      } on TimeoutException catch (e) {
        throw WebDavRequestException(
          'WebDAV pull request timed out',
          path: relativePath,
          cause: e,
        );
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final Map<String, dynamic> json = _decodeJsonObject(response);
        final SyncBatch batch = SyncBatch.fromJson(json);
        result.add(
          PulledSyncBatch(
            batch: batch,
            cursorAt: lastModified ?? batch.createdAt,
          ),
        );
      } else if (!(response.statusCode == 404 || response.statusCode == 409)) {
        throw WebDavRequestException(
          'WebDAV pull file failed',
          statusCode: response.statusCode,
          path: relativePath,
          responseBody: _decodeResponseBody(response),
        );
      }
    }

    result.sort((PulledSyncBatch a, PulledSyncBatch b) {
      final int cursorCompare = a.cursorAt.compareTo(b.cursorAt);
      if (cursorCompare != 0) return cursorCompare;
      return a.batch.createdAt.compareTo(b.batch.createdAt);
    });
    return result;
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
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
    final Uri uri = _buildUri(path);
    final http.Request request = http.Request('MKCOL', uri);
    request.headers.addAll(_headers());
    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(_requestTimeout);
    } on TimeoutException catch (e) {
      throw WebDavRequestException(
        'WebDAV MKCOL request timed out',
        path: path,
        cause: e,
      );
    }
    if (!(response.statusCode == 201 || response.statusCode == 405)) {
      throw WebDavRequestException(
        'MKCOL failed',
        statusCode: response.statusCode,
        path: path,
      );
    }
  }

  Future<List<_DavEntry>> _listOpsJsonFilesForDevicesRoot(
    String devicesRootPath,
  ) async {
    final String normalizedRoot = _normalizePath(devicesRootPath);
    final List<_DavEntry> devices = await _propfind(normalizedRoot);
    final List<_DavEntry> files = <_DavEntry>[];

    for (final _DavEntry device in devices) {
      if (!device.isCollection || _samePath(device.path, normalizedRoot)) {
        continue;
      }

      final String normalizedDevice = _normalizePath(
        device.path,
      ).replaceFirst(RegExp(r'/+$'), '');
      final String opsPath = '$normalizedDevice/ops/';
      final List<_DavEntry> entries = await _propfind(opsPath);
      for (final _DavEntry entry in entries) {
        if (_samePath(entry.path, opsPath) || entry.isCollection) {
          continue;
        }
        if (entry.path.toLowerCase().endsWith('.json')) {
          files.add(entry);
        }
      }
    }

    return files;
  }

  Future<List<_DavEntry>> _propfind(String path) async {
    final Uri uri = _buildUri(path);
    final http.Request request = http.Request('PROPFIND', uri);
    request.headers.addAll(
      _headers(contentType: 'application/xml')
        ..addAll(<String, String>{'Depth': '1'}),
    );
    request.body =
        '<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getlastmodified/></d:prop></d:propfind>';

    final http.StreamedResponse streamed;
    try {
      streamed = await _client.send(request).timeout(_requestTimeout);
    } on TimeoutException catch (e) {
      throw WebDavRequestException(
        'PROPFIND request timed out',
        path: path,
        cause: e,
      );
    }
    final http.Response response = await http.Response.fromStream(streamed);

    if (!(response.statusCode == 207 ||
        (response.statusCode >= 200 && response.statusCode < 300))) {
      if (response.statusCode == 404 || response.statusCode == 409) {
        return <_DavEntry>[];
      }
      throw WebDavRequestException(
        'PROPFIND failed',
        statusCode: response.statusCode,
        path: path,
        responseBody: _decodeResponseBody(response),
      );
    }

    final XmlDocument doc = XmlDocument.parse(_decodeResponseBody(response));
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
      for (final XmlElement rt in _findAllByLocalName(
        element,
        'resourcetype',
      )) {
        if (_findAllByLocalName(rt, 'collection').isNotEmpty) {
          isCollection = true;
          break;
        }
      }

      DateTime? lastModified;
      XmlElement? modifiedNode;
      for (final XmlElement node in _findAllByLocalName(
        element,
        'getlastmodified',
      )) {
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
      return _toDavRelativePath(uri.path);
    }
    return _toDavRelativePath(href);
  }

  bool _samePath(String a, String b) {
    return _normalizePath(a).replaceFirst(RegExp(r'/+$'), '') ==
        _normalizePath(b).replaceFirst(RegExp(r'/+$'), '');
  }

  String _normalizePath(String path) {
    final String withLeading = path.startsWith('/') ? path : '/$path';
    return withLeading.replaceAll(RegExp(r'/{2,}'), '/');
  }

  String _normalizedBasePath() {
    final String normalized = _normalizePath(
      _baseUri.path,
    ).replaceFirst(RegExp(r'/+$'), '');
    if (normalized == '/') {
      return '';
    }
    return normalized;
  }

  String _toDavRelativePath(String rawPath) {
    final String normalized = _normalizePath(rawPath);
    final String basePath = _normalizedBasePath();
    if (basePath.isEmpty) {
      return normalized;
    }
    if (normalized == basePath) {
      return '/';
    }
    if (normalized.startsWith('$basePath/')) {
      return normalized.substring(basePath.length);
    }
    return normalized;
  }

  Uri _buildUri(String path) {
    final String normalized = _normalizePath(path);
    final String basePath = _normalizedBasePath();
    final String requestPath;
    if (basePath.isEmpty) {
      requestPath = normalized;
    } else if (normalized == basePath || normalized.startsWith('$basePath/')) {
      requestPath = normalized;
    } else {
      requestPath = _normalizePath('$basePath$normalized');
    }
    return _baseUri.replace(path: requestPath);
  }

  static Uri _parseBaseUri(String rawBaseUrl) {
    final Uri uri = Uri.parse(rawBaseUrl.trim());
    if (uri.scheme.toLowerCase() != 'https' || !uri.hasAuthority) {
      throw ArgumentError('WebDAV base URL must use https://');
    }
    final String normalizedPath =
        uri.path.isEmpty ? '' : uri.path.replaceFirst(RegExp(r'/+$'), '');
    return uri.replace(path: normalizedPath, query: null, fragment: null);
  }

  Iterable<XmlElement> _findAllByLocalName(XmlNode node, String localName) {
    return node.descendants.whereType<XmlElement>().where(
          (XmlElement element) => element.name.local == localName,
        );
  }

  String _encodePathSegment(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('WebDAV path segment cannot be empty');
    }
    return Uri.encodeComponent(trimmed);
  }

  Map<String, dynamic> _decodeJsonObject(http.Response response) {
    final dynamic decoded = jsonDecode(_decodeResponseBody(response));
    if (decoded is! Map<String, dynamic>) {
      throw Exception('WebDAV JSON payload must be an object');
    }
    return decoded;
  }

  String _decodeResponseBody(http.Response response) {
    final List<int> bytes = response.bodyBytes;
    if (bytes.isEmpty) {
      return '';
    }

    final String? declaredCharset = _extractCharset(response);
    if (declaredCharset != null) {
      final Encoding? declared = Charset.getByName(declaredCharset);
      if (declared != null) {
        try {
          return declared.decode(bytes);
        } catch (_) {}
      }
    }

    try {
      return utf8.decode(bytes);
    } catch (_) {}

    final Encoding? detected = Charset.detect(bytes, defaultEncoding: latin1);
    if (detected != null) {
      try {
        return detected.decode(bytes);
      } catch (_) {}
    }

    return latin1.decode(bytes);
  }

  String? _extractCharset(http.Response response) {
    final String contentType = response.headers['content-type'] ?? '';
    final Match? match = RegExp(
      r'''charset\s*=\s*["']?([A-Za-z0-9._\-]+)''',
      caseSensitive: false,
    ).firstMatch(contentType);
    final String? charset = match?.group(1)?.trim();
    if (charset == null || charset.isEmpty) {
      return null;
    }
    return charset;
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

class WebDavRequestException implements Exception {
  const WebDavRequestException(
    this.message, {
    this.statusCode,
    this.path,
    this.responseBody,
    this.cause,
  });

  final String message;
  final int? statusCode;
  final String? path;
  final String? responseBody;
  final Object? cause;

  @override
  String toString() {
    final StringBuffer buffer = StringBuffer(message);
    if (statusCode != null) {
      buffer.write(' (status=$statusCode)');
    }
    if (path != null && path!.isNotEmpty) {
      buffer.write(', path=$path');
    }
    if (responseBody != null && responseBody!.trim().isNotEmpty) {
      final String trimmed = responseBody!.trim();
      final String snippet =
          trimmed.length <= 180 ? trimmed : '${trimmed.substring(0, 180)}...';
      buffer.write(', body=$snippet');
    }
    if (cause != null) {
      buffer.write(', cause=$cause');
    }
    return buffer.toString();
  }
}
