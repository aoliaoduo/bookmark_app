import 'dart:convert';
import 'dart:async';

import 'package:charset/charset.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

class MetadataFetchException implements Exception {
  const MetadataFetchException(this.message);

  final String message;

  @override
  String toString() => message;
}

class UrlMetadata {
  const UrlMetadata({
    required this.finalUrl,
    required this.title,
    required this.fetchedAt,
    required this.statusCode,
  });

  final String finalUrl;
  final String? title;
  final DateTime fetchedAt;
  final int statusCode;
}

class MetadataFetchService {
  MetadataFetchService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  Future<UrlMetadata> fetchTitle(String url) async {
    final Uri uri = Uri.parse(url);
    http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: <String, String>{
          'User-Agent': 'BookmarkAppBot/1.0',
          'Accept': 'text/html,application/xhtml+xml',
        },
      ).timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw const MetadataFetchException('请求超时，请稍后重试');
    } catch (_) {
      throw const MetadataFetchException('无法连接该链接，请检查是否可访问');
    }

    if (response.statusCode >= 400) {
      throw MetadataFetchException('目标站返回 ${response.statusCode}，可能拒绝访问');
    }

    final String contentType = response.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().contains('text/html')) {
      throw const MetadataFetchException('链接返回的不是网页内容，无法提取标题');
    }

    String? title;
    final String body = _decodeBody(response);
    final document = html_parser.parse(body);
    final titleNode = document.querySelector('title');
    title = titleNode?.text.trim();
    if (title == null || title.isEmpty) {
      throw const MetadataFetchException('页面缺少可识别标题');
    }

    return UrlMetadata(
      finalUrl: response.request?.url.toString() ?? url,
      title: title,
      fetchedAt: DateTime.now().toUtc(),
      statusCode: response.statusCode,
    );
  }

  String _decodeBody(http.Response response) {
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
    } catch (_) {
      final Encoding? detected = Charset.detect(bytes, defaultEncoding: latin1);
      if (detected != null) {
        try {
          return detected.decode(bytes);
        } catch (_) {}
      }
      return latin1.decode(bytes);
    }
  }

  String? _extractCharset(http.Response response) {
    final String contentType = response.headers['content-type'] ?? '';
    final Match? headerMatch = RegExp(
      r'''charset\s*=\s*["']?([A-Za-z0-9._\-]+)''',
      caseSensitive: false,
    ).firstMatch(contentType);
    final String? headerCharset = headerMatch?.group(1)?.trim();
    if (headerCharset != null && headerCharset.isNotEmpty) {
      return headerCharset;
    }

    final List<int> bytes = response.bodyBytes;
    if (bytes.isEmpty) {
      return null;
    }
    final int inspectLength = bytes.length < 4096 ? bytes.length : 4096;
    final String head = latin1.decode(bytes.sublist(0, inspectLength));
    final Match? metaMatch = RegExp(
      r'''charset\s*=\s*["']?\s*([A-Za-z0-9._\-]+)''',
      caseSensitive: false,
    ).firstMatch(head);
    final String? metaCharset = metaMatch?.group(1)?.trim();
    if (metaCharset == null || metaCharset.isEmpty) {
      return null;
    }
    return metaCharset;
  }
}
