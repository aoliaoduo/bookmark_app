import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class SlimDownResult {
  const SlimDownResult({
    required this.cleanedCacheFiles,
    required this.cleanedCacheBytes,
    required this.purgedOutboxRows,
    required this.purgedTrashRows,
    required this.dbBytesBefore,
    required this.dbBytesAfter,
  });

  final int cleanedCacheFiles;
  final int cleanedCacheBytes;
  final int purgedOutboxRows;
  final int purgedTrashRows;
  final int dbBytesBefore;
  final int dbBytesAfter;
}

class MaintenanceService {
  MaintenanceService({required Database db}) : _db = db;

  final Database _db;

  Future<SlimDownResult> slimDown({
    Duration outboxRetention = const Duration(days: 30),
    Duration trashRetention = const Duration(days: 30),
  }) async {
    final DateTime now = DateTime.now().toUtc();

    final int dbBytesBefore = await _safeDbSize();

    final String outboxCutoff = now.subtract(outboxRetention).toIso8601String();
    final int purgedOutboxRows = await _db.delete(
      'sync_outbox',
      where: 'pushed = 1 AND occurred_at < ?',
      whereArgs: <Object?>[outboxCutoff],
    );

    final String trashCutoff = now.subtract(trashRetention).toIso8601String();
    final int purgedTrashRows = await _db.delete(
      'bookmarks',
      where: 'deleted_at IS NOT NULL AND deleted_at < ?',
      whereArgs: <Object?>[trashCutoff],
    );

    await _db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    await _db.execute('VACUUM');
    await _db.execute('PRAGMA optimize');

    final _CacheCleanResult cacheResult = await _clearTemporaryFiles();
    final int dbBytesAfter = await _safeDbSize();

    return SlimDownResult(
      cleanedCacheFiles: cacheResult.files,
      cleanedCacheBytes: cacheResult.bytes,
      purgedOutboxRows: purgedOutboxRows,
      purgedTrashRows: purgedTrashRows,
      dbBytesBefore: dbBytesBefore,
      dbBytesAfter: dbBytesAfter,
    );
  }

  Future<int> _safeDbSize() async {
    try {
      final File file = File(_db.path);
      if (!await file.exists()) return 0;
      return (await file.length());
    } catch (_) {
      return 0;
    }
  }

  Future<_CacheCleanResult> _clearTemporaryFiles() async {
    try {
      final Directory tempDir = await getTemporaryDirectory();
      if (!await tempDir.exists()) {
        return const _CacheCleanResult(files: 0, bytes: 0);
      }

      int files = 0;
      int bytes = 0;
      await for (final FileSystemEntity entity
          in tempDir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          files += 1;
          try {
            bytes += await entity.length();
            await entity.delete();
          } catch (_) {
            // 某些临时文件可能被系统占用，忽略并继续。
          }
        }
      }

      return _CacheCleanResult(files: files, bytes: bytes);
    } catch (_) {
      return const _CacheCleanResult(files: 0, bytes: 0);
    }
  }
}

class _CacheCleanResult {
  const _CacheCleanResult({required this.files, required this.bytes});

  final int files;
  final int bytes;
}
