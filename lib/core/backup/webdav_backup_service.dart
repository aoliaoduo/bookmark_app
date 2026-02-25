import 'dart:async';
import 'dart:convert';

import 'package:charset/charset.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../domain/bookmark.dart';
import '../sync/webdav_sync_provider.dart';

class WebDavBackupService {
  WebDavBackupService({
    required WebDavConfig config,
    http.Client? client,
    Duration requestTimeout = const Duration(seconds: 25),
  }) : _config = config,
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _baseUri = _parseBaseUri(config.baseUrl),
       _requestTimeout = requestTimeout;

  final WebDavConfig _config;
  final http.Client _client;
  final bool _ownsClient;
  final Uri _baseUri;
  final Duration _requestTimeout;

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  Future<void> uploadSnapshot({
    required String userId,
    required List<Bookmark> bookmarks,
    DateTime? timestamp,
  }) async {
    final DateTime now = (timestamp ?? DateTime.now()).toUtc();
    final String name = _snapshotFileName(now);
    final String snapshotsDir = _snapshotsDir(userId);
    final String path = '$snapshotsDir/$name';

    await _mkcol('/BookmarksApp');
    await _mkcol('/BookmarksApp/users');
    await _mkcol(_userDir(userId));
    await _mkcol(snapshotsDir);

    final Uri uri = _buildUri(path);
    final List<Map<String, dynamic>> bookmarkObjects = bookmarks
        .map((Bookmark b) => b.toJson())
        .toList();
    final String digest = _snapshotDigest(bookmarkObjects);
    final String payload = jsonEncode(<String, dynamic>{
      'schemaVersion': 2,
      'createdAt': now.toIso8601String(),
      'bookmarkCount': bookmarkObjects.length,
      'digestSha256': digest,
      'bookmarks': bookmarkObjects,
    });

    final http.Response response;
    try {
      response = await _client
          .put(
            uri,
            headers: _headers(contentType: 'application/json'),
            body: payload,
          )
          .timeout(_requestTimeout);
    } on TimeoutException catch (e) {
      throw WebDavRequestException(
        'Snapshot upload timed out',
        path: path,
        cause: e,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WebDavRequestException(
        'Snapshot upload failed',
        statusCode: response.statusCode,
        path: path,
        responseBody: _decodeResponseBody(response),
      );
    }
  }

  Future<void> uploadMarkdownSnapshot({
    required String userId,
    required String markdown,
    DateTime? timestamp,
  }) async {
    final DateTime now = (timestamp ?? DateTime.now()).toUtc();
    final String name = _markdownFileName(now);
    final String markdownDir = _markdownDir(userId);
    final String path = '$markdownDir/$name';

    await _mkcol('/BookmarksApp');
    await _mkcol('/BookmarksApp/users');
    await _mkcol(_userDir(userId));
    await _mkcol(markdownDir);

    final Uri uri = _buildUri(path);
    final http.Response response;
    try {
      response = await _client
          .put(
            uri,
            headers: _headers(contentType: 'text/markdown; charset=utf-8'),
            body: markdown,
          )
          .timeout(_requestTimeout);
    } on TimeoutException catch (e) {
      throw WebDavRequestException(
        'Markdown snapshot upload timed out',
        path: path,
        cause: e,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WebDavRequestException(
        'Markdown snapshot upload failed',
        statusCode: response.statusCode,
        path: path,
        responseBody: _decodeResponseBody(response),
      );
    }
  }

  Future<List<Bookmark>> downloadSnapshot({
    required String userId,
    required String snapshotFileName,
  }) async {
    final String encodedName = _encodePathSegment(snapshotFileName);
    final String path = '${_snapshotsDir(userId)}/$encodedName';
    final Uri uri = _buildUri(path);
    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: _headers())
          .timeout(_requestTimeout);
    } on TimeoutException catch (e) {
      throw WebDavRequestException(
        'Snapshot download timed out',
        path: path,
        cause: e,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WebDavRequestException(
        'Snapshot download failed',
        statusCode: response.statusCode,
        path: path,
        responseBody: _decodeResponseBody(response),
      );
    }
    final Map<String, dynamic> json = _decodeJsonObject(response);
    final List<dynamic> rawBookmarks =
        json['bookmarks'] as List<dynamic>? ?? const <dynamic>[];
    final List<Map<String, dynamic>> bookmarkObjects = rawBookmarks
        .map((dynamic e) => e as Map<String, dynamic>)
        .toList();
    _validateSnapshot(json, bookmarkObjects);
    return bookmarkObjects.map(Bookmark.fromJson).toList();
  }

  Future<void> _mkcol(String path) async {
    final Uri uri = _buildUri(path);
    final http.Request request = http.Request('MKCOL', uri);
    request.headers.addAll(_headers());
    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(_requestTimeout);
    } on TimeoutException catch (e) {
      throw WebDavRequestException('MKCOL timed out', path: path, cause: e);
    }
    if (!(response.statusCode == 201 || response.statusCode == 405)) {
      throw WebDavRequestException(
        'MKCOL failed',
        statusCode: response.statusCode,
        path: path,
      );
    }
  }

  Map<String, String> _headers({String? contentType}) {
    final String token = base64Encode(
      utf8.encode('${_config.username}:${_config.password}'),
    );
    return <String, String>{
      'Authorization': 'Basic $token',
      if (contentType != null) 'Content-Type': contentType,
    };
  }

  String _snapshotFileName(DateTime now) {
    final String ts = now
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    return 'bookmarks_$ts.json';
  }

  String _markdownFileName(DateTime now) {
    final String ts = now
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    return 'bookmarks_links_$ts.md';
  }

  String _userDir(String userId) {
    return '/BookmarksApp/users/${_encodePathSegment(userId)}';
  }

  String _snapshotsDir(String userId) {
    return '${_userDir(userId)}/snapshots';
  }

  String _markdownDir(String userId) {
    return '${_userDir(userId)}/markdown';
  }

  String _snapshotDigest(List<Map<String, dynamic>> bookmarks) {
    final String canonical = jsonEncode(bookmarks);
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  void _validateSnapshot(
    Map<String, dynamic> snapshot,
    List<Map<String, dynamic>> bookmarks,
  ) {
    final Object? bookmarkCountRaw = snapshot['bookmarkCount'];
    if (bookmarkCountRaw is num &&
        bookmarkCountRaw.toInt() != bookmarks.length) {
      throw const FormatException('备份文件校验失败：bookmarkCount 不匹配');
    }

    final String digest = (snapshot['digestSha256'] as String?)?.trim() ?? '';
    if (digest.isEmpty) {
      return;
    }
    final String actual = _snapshotDigest(bookmarks);
    if (actual != digest) {
      throw const FormatException('备份文件校验失败：digest 不匹配，文件可能已损坏');
    }
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

  static Uri _parseBaseUri(String rawBaseUrl) {
    final Uri uri = Uri.parse(rawBaseUrl.trim());
    final String normalizedPath = uri.path.isEmpty
        ? ''
        : uri.path.replaceFirst(RegExp(r'/+$'), '');
    return uri.replace(path: normalizedPath, query: null, fragment: null);
  }

  Map<String, dynamic> _decodeJsonObject(http.Response response) {
    final dynamic decoded = jsonDecode(_decodeResponseBody(response));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('备份文件格式不正确：JSON 根节点必须是对象');
    }
    return decoded;
  }

  String _decodeResponseBody(http.Response response) {
    final List<int> bytes = response.bodyBytes;
    if (bytes.isEmpty) return '';

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
    if (charset == null || charset.isEmpty) return null;
    return charset;
  }

  String _encodePathSegment(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('WebDAV path segment cannot be empty');
    }
    return Uri.encodeComponent(trimmed);
  }
}
