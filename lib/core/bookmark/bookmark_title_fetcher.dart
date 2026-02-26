import 'dart:convert';

import 'package:http/http.dart' as http;

class BookmarkTitleFetcher {
  Future<String> fetchTitle(String url) async {
    final Uri uri = Uri.parse(url);
    final http.Response response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('请求失败：HTTP ${response.statusCode}');
    }

    final String title = extractTitleFromHtmlBytes(
      response.bodyBytes,
      contentType: response.headers['content-type'],
    );
    if (title.isEmpty) {
      throw Exception('页面没有可用标题');
    }
    return title;
  }

  String extractTitleFromHtmlBytes(List<int> bytes, {String? contentType}) {
    final String? headerCharset = _charsetFromContentType(contentType);
    final List<Encoding> candidates = <Encoding>[];

    if (headerCharset != null) {
      final Encoding? byHeader = _encodingByName(headerCharset);
      if (byHeader != null) {
        candidates.add(byHeader);
      }
    }

    candidates.addAll(<Encoding>[utf8, latin1]);

    final Set<Encoding> dedup = <Encoding>{};
    for (final encoding in candidates) {
      if (!dedup.add(encoding)) {
        continue;
      }
      final String html = _decode(bytes, encoding);
      final String title = extractTitleFromHtml(html);
      if (title.isNotEmpty) {
        return title;
      }

      final String? metaCharset = _charsetFromMeta(html);
      if (metaCharset != null) {
        final Encoding? metaEncoding = _encodingByName(metaCharset);
        if (metaEncoding != null && dedup.add(metaEncoding)) {
          final String htmlByMeta = _decode(bytes, metaEncoding);
          final String titleByMeta = extractTitleFromHtml(htmlByMeta);
          if (titleByMeta.isNotEmpty) {
            return titleByMeta;
          }
        }
      }
    }

    return '';
  }

  String extractTitleFromHtml(String html) {
    final RegExp regExp = RegExp(
      r'<title[^>]*>([\s\S]*?)</title>',
      caseSensitive: false,
    );
    final RegExpMatch? match = regExp.firstMatch(html);
    if (match == null) {
      return '';
    }
    return _normalizeWhitespace(_decodeHtmlEntities(match.group(1) ?? ''));
  }

  String _normalizeWhitespace(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _decodeHtmlEntities(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }

  String? _charsetFromContentType(String? contentType) {
    if (contentType == null) {
      return null;
    }
    final RegExp regExp = RegExp(r'charset=([^;]+)', caseSensitive: false);
    final RegExpMatch? match = regExp.firstMatch(contentType);
    return match?.group(1)?.trim();
  }

  String? _charsetFromMeta(String html) {
    final RegExp regExp = RegExp(
      r'<meta[^>]+charset\s*=\s*"?([^\s"/>]+)',
      caseSensitive: false,
    );
    final RegExpMatch? match = regExp.firstMatch(html);
    return match?.group(1)?.trim();
  }

  Encoding? _encodingByName(String name) {
    switch (name.toLowerCase()) {
      case 'utf-8':
      case 'utf8':
        return utf8;
      case 'latin1':
      case 'iso-8859-1':
      case 'gbk':
      case 'gb2312':
      case 'gb18030':
        // M3 first version: use latin1 as non-utf fallback for compatibility.
        return latin1;
      default:
        return null;
    }
  }

  String _decode(List<int> bytes, Encoding encoding) {
    if (encoding == utf8) {
      return utf8.decode(bytes, allowMalformed: true);
    }
    try {
      return encoding.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }
}
