import 'dart:convert';

import 'package:code/core/bookmark/bookmark_title_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extract title from html bytes', () {
    final fetcher = BookmarkTitleFetcher();
    final bytes = utf8.encode(
      '<html><head><title>  示例标题 &amp; Test </title></head></html>',
    );

    final title = fetcher.extractTitleFromHtmlBytes(bytes);
    expect(title, '示例标题 & Test');
  });
}
