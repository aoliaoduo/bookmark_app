import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/bookmark.dart';
import '../sync/webdav_sync_provider.dart';

class WebDavBackupService {
  WebDavBackupService({required WebDavConfig config, http.Client? client})
      : _config = config,
        _client = client ?? http.Client();

  final WebDavConfig _config;
  final http.Client _client;

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

    final Uri uri = Uri.parse('${_config.baseUrl}$path');
    final String payload = jsonEncode(<String, dynamic>{
      'createdAt': now.toIso8601String(),
      'bookmarks': bookmarks.map((Bookmark b) => b.toJson()).toList(),
    });

    final http.Response response = await _client.put(
      uri,
      headers: _headers(contentType: 'application/json'),
      body: payload,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Snapshot upload failed: ${response.statusCode} ${response.body}',
      );
    }
  }

  Future<List<Bookmark>> downloadSnapshot({
    required String userId,
    required String snapshotFileName,
  }) async {
    final String encodedName = _encodePathSegment(snapshotFileName);
    final Uri uri = Uri.parse(
      '${_config.baseUrl}${_snapshotsDir(userId)}/$encodedName',
    );
    final http.Response response = await _client.get(uri, headers: _headers());
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Snapshot download failed: ${response.statusCode} ${response.body}',
      );
    }
    final Map<String, dynamic> json =
        jsonDecode(response.body) as Map<String, dynamic>;
    return (json['bookmarks'] as List<dynamic>)
        .map((dynamic e) => Bookmark.fromJson(e as Map<String, dynamic>))
        .toList();
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
    final String ts =
        now.toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
    return 'bookmarks_$ts.json';
  }

  String _userDir(String userId) {
    return '/BookmarksApp/users/${_encodePathSegment(userId)}';
  }

  String _snapshotsDir(String userId) {
    return '${_userDir(userId)}/snapshots';
  }

  String _encodePathSegment(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('WebDAV path segment cannot be empty');
    }
    return Uri.encodeComponent(trimmed);
  }
}
