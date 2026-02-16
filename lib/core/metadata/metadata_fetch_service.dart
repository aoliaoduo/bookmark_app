import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

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
    final http.Response response = await _client.get(
      uri,
      headers: <String, String>{
        'User-Agent': 'BookmarkAppBot/1.0',
        'Accept': 'text/html,application/xhtml+xml',
      },
    );

    String? title;
    if ((response.headers['content-type'] ?? '').contains('text/html')) {
      final String body = _decodeBody(response);
      final document = html_parser.parse(body);
      final titleNode = document.querySelector('title');
      title = titleNode?.text.trim();
      if (title != null && title.isEmpty) {
        title = null;
      }
    }

    return UrlMetadata(
      finalUrl: response.request?.url.toString() ?? url,
      title: title,
      fetchedAt: DateTime.now().toUtc(),
      statusCode: response.statusCode,
    );
  }

  String _decodeBody(http.Response response) {
    // 尽量按字节解码，避免中文网站标题乱码。
    try {
      return utf8.decode(response.bodyBytes);
    } catch (_) {
      return response.body;
    }
  }
}
