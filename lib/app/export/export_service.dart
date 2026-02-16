import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/domain/bookmark.dart';

enum ExportFormat { json, csv }

class ExportResult {
  const ExportResult({
    required this.path,
    required this.count,
    required this.format,
  });

  final String path;
  final int count;
  final ExportFormat format;
}

class ExportService {
  String defaultFileName(
      {required ExportFormat format, required String prefix}) {
    final DateTime now = DateTime.now();
    final String ts =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final String ext = format == ExportFormat.json ? 'json' : 'csv';
    return '${prefix}_$ts.$ext';
  }

  Future<ExportResult> exportBookmarks({
    required List<Bookmark> bookmarks,
    required ExportFormat format,
    required String targetPath,
  }) async {
    final File file = File(_normalizeTargetPath(targetPath, format));
    await file.parent.create(recursive: true);

    if (format == ExportFormat.json) {
      final List<Map<String, dynamic>> data =
          bookmarks.map((Bookmark b) => b.toJson()).toList();
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
      );
    } else {
      final StringBuffer csv = StringBuffer();
      csv.writeln(
        'id,url,normalizedUrl,title,note,tags,createdAt,updatedAt,deletedAt,titleUpdatedAt',
      );
      for (final Bookmark b in bookmarks) {
        csv.writeln(
          <String>[
            b.id,
            b.url,
            b.normalizedUrl,
            b.title ?? '',
            b.note ?? '',
            b.tags.join('|'),
            b.createdAt.toIso8601String(),
            b.updatedAt.toIso8601String(),
            b.deletedAt?.toIso8601String() ?? '',
            b.titleUpdatedAt?.toIso8601String() ?? '',
          ].map(_escapeCsv).join(','),
        );
      }
      await file.writeAsString(csv.toString());
    }

    return ExportResult(
        path: file.path, count: bookmarks.length, format: format);
  }

  String _normalizeTargetPath(String targetPath, ExportFormat format) {
    final String trimmed = targetPath.trim();
    final String ext = format == ExportFormat.json ? '.json' : '.csv';
    if (trimmed.toLowerCase().endsWith(ext)) {
      return trimmed;
    }
    return p.setExtension(trimmed, ext);
  }

  String _escapeCsv(String value) {
    final bool needQuote =
        value.contains(',') || value.contains('"') || value.contains('\n');
    if (!needQuote) {
      return value;
    }
    return '"${value.replaceAll('"', '""')}"';
  }
}
