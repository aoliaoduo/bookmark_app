import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../sync_engine.dart';
import 'webdav_config.dart';

class WebDavFileEntry {
  const WebDavFileEntry({
    required this.path,
    required this.isCollection,
    this.sizeBytes,
    this.lastModified,
  });

  final String path;
  final bool isCollection;
  final int? sizeBytes;
  final DateTime? lastModified;
}

class WebDavStorageClient {
  WebDavStorageClient({required this.config, http.Client? client})
    : _client = client ?? http.Client() {
    _baseUri = Uri.parse(_normalizeBaseUrl(config.baseUrl));
  }

  final WebDavConfig config;
  final http.Client _client;
  late final Uri _baseUri;

  static const String _propfindBody = '''<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:"><d:allprop/></d:propfind>''';

  Future<void> ensureDirectory(String path) async {
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

  Future<void> uploadBytes(
    String path,
    Uint8List bytes, {
    String contentType = 'application/octet-stream',
  }) async {
    await _request(
      method: 'PUT',
      path: path,
      bytes: bytes,
      headers: <String, String>{'Content-Type': contentType},
      acceptedStatus: const <int>{200, 201, 204},
    );
  }

  Future<Uint8List> downloadBytes(String path) async {
    final _StorageResponse response = await _request(
      method: 'GET',
      path: path,
      acceptedStatus: const <int>{200},
    );
    return response.bytes;
  }

  Future<void> delete(String path) async {
    await _request(
      method: 'DELETE',
      path: path,
      acceptedStatus: const <int>{200, 202, 204, 404},
    );
  }

  Future<List<WebDavFileEntry>> listDirectory(String path) async {
    final _StorageResponse response = await _request(
      method: 'PROPFIND',
      path: path,
      headers: const <String, String>{'Depth': '1'},
      body: _propfindBody,
      acceptedStatus: const <int>{207, 404},
    );
    if (response.statusCode == 404) {
      return const <WebDavFileEntry>[];
    }
    return _parsePropfind(path, response.body);
  }

  Future<_StorageResponse> _request({
    required String method,
    required String path,
    Set<int> acceptedStatus = const <int>{200},
    Map<String, String>? headers,
    String? body,
    Uint8List? bytes,
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
    if (bytes != null) {
      request.bodyBytes = bytes;
    } else if (body != null) {
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
    return _StorageResponse(
      statusCode: response.statusCode,
      body: response.body,
      bytes: response.bodyBytes,
    );
  }

  List<WebDavFileEntry> _parsePropfind(String targetPath, String body) {
    final List<WebDavFileEntry> entries = <WebDavFileEntry>[];
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
    final RegExp sizeExp = RegExp(
      r'<[^>]*getcontentlength[^>]*>(\d+)</[^>]*getcontentlength>',
      caseSensitive: false,
    );
    final RegExp modifiedExp = RegExp(
      r'<[^>]*getlastmodified[^>]*>([^<]+)</[^>]*getlastmodified>',
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
      final int? sizeBytes = int.tryParse(
        sizeExp.firstMatch(block)?.group(1) ?? '',
      );
      final String? modifiedRaw = modifiedExp
          .firstMatch(block)
          ?.group(1)
          ?.trim();
      final DateTime? modifiedAt = modifiedRaw == null
          ? null
          : DateTime.tryParse(modifiedRaw)?.toLocal();
      entries.add(
        WebDavFileEntry(
          path: relativePath,
          isCollection: collectionExp.hasMatch(block),
          sizeBytes: sizeBytes,
          lastModified: modifiedAt,
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
    String normalized = path.trim().replaceAll('\\', '/');
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  String _buildAuthHeader() {
    final String token = base64Encode(
      utf8.encode('${config.username}:${config.appPassword}'),
    );
    return 'Basic $token';
  }

  String _normalizeBaseUrl(String raw) {
    String url = raw.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return '$url/';
  }
}

class _StorageResponse {
  const _StorageResponse({
    required this.statusCode,
    required this.body,
    required this.bytes,
  });

  final int statusCode;
  final String body;
  final Uint8List bytes;
}
