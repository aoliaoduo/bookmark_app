import 'dart:io';

import 'package:bookmark_app/app/export/export_service.dart';
import 'package:bookmark_app/core/domain/bookmark.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ExportService markdown', () {
    late Directory tempDir;
    late ExportService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('bookmark_export_test_');
      service = ExportService();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('exports markdown links with one blank line between entries',
        () async {
      final List<Bookmark> bookmarks = <Bookmark>[
        _bookmark(id: '1', url: 'https://example.com/1', title: '标题1'),
        _bookmark(id: '2', url: 'https://example.com/2', title: '标题2'),
      ];

      final String targetPath = p.join(tempDir.path, 'bookmarks_export');
      final ExportResult result = await service.exportBookmarks(
        bookmarks: bookmarks,
        format: ExportFormat.md,
        targetPath: targetPath,
      );

      expect(result.format, ExportFormat.md);
      expect(result.count, 2);
      expect(result.path.endsWith('.md'), isTrue);

      final String content = await File(result.path).readAsString();
      expect(
        content,
        '[标题1](https://example.com/1)\n\n[标题2](https://example.com/2)\n',
      );
    });

    test('markdown export falls back to url when title is empty', () async {
      final List<Bookmark> bookmarks = <Bookmark>[
        _bookmark(id: '1', url: 'https://example.com/only', title: null),
      ];

      final ExportResult result = await service.exportBookmarks(
        bookmarks: bookmarks,
        format: ExportFormat.md,
        targetPath: p.join(tempDir.path, 'single'),
      );

      final String content = await File(result.path).readAsString();
      expect(content, '[https://example.com/only](https://example.com/only)\n');
    });

    test('default filename supports md extension', () {
      final String fileName =
          service.defaultFileName(format: ExportFormat.md, prefix: 'bookmarks');

      expect(fileName.endsWith('.md'), isTrue);
    });
  });
}

Bookmark _bookmark({
  required String id,
  required String url,
  required String? title,
}) {
  final DateTime now = DateTime.utc(2026, 2, 17, 0, 0, 0);
  return Bookmark(
    id: id,
    url: url,
    normalizedUrl: url,
    createdAt: now,
    updatedAt: now,
    title: title,
  );
}
