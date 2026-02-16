import 'dart:io';

import 'package:sqflite/sqflite.dart';

class SlimDownResult {
  const SlimDownResult({
    required this.purgedOutboxRows,
    required this.purgedTrashRows,
    required this.purgedInvalidRows,
    required this.dbBytesBefore,
    required this.dbBytesAfter,
  });

  final int purgedOutboxRows;
  final int purgedTrashRows;
  final int purgedInvalidRows;
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

    // 清理意外写入的无效数据，避免无用脏记录持续占用空间。
    final int purgedInvalidRows = await _db.delete(
      'bookmarks',
      where: "trim(url) = '' OR trim(normalized_url) = ''",
    );

    await _db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    await _db.execute('VACUUM');
    await _db.execute('PRAGMA optimize');

    final int dbBytesAfter = await _safeDbSize();

    return SlimDownResult(
      purgedOutboxRows: purgedOutboxRows,
      purgedTrashRows: purgedTrashRows,
      purgedInvalidRows: purgedInvalidRows,
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
}
