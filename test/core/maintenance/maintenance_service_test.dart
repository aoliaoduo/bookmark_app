import 'dart:io';

import 'package:code/core/clock/app_clock.dart';
import 'package:code/core/db/app_database.dart';
import 'package:code/core/maintenance/maintenance_service.dart';
import 'package:code/core/search/fts_updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FixedClock implements AppClock {
  const _FixedClock(this.value);

  final int value;

  @override
  int nowMs() => value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('purgeNoteHistoryKeepLatest keeps only latest version', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'maintenance_test_',
    );
    final String dbPath = p.join(tempDir.path, 'main.db');
    final AppDatabase db = await AppDatabase.open(databasePath: dbPath);
    final MaintenanceService service = MaintenanceService(
      database: db,
      clock: const _FixedClock(1_730_000_000_000),
      ftsUpdater: FtsUpdater(),
    );

    await db.db.insert('notes', <String, Object?>{
      'id': 'n1',
      'title': 'note',
      'raw_text': 'raw',
      'latest_version': 3,
      'created_at': 1,
      'updated_at': 1,
      'deleted': 0,
      'lamport': 1,
      'device_id': 'd1',
    });
    await db.db.insert('note_versions', <String, Object?>{
      'note_id': 'n1',
      'version': 1,
      'organized_md': 'v1',
      'created_at': 1,
    });
    await db.db.insert('note_versions', <String, Object?>{
      'note_id': 'n1',
      'version': 2,
      'organized_md': 'v2',
      'created_at': 1,
    });
    await db.db.insert('note_versions', <String, Object?>{
      'note_id': 'n1',
      'version': 3,
      'organized_md': 'v3',
      'created_at': 1,
    });

    await service.purgeNoteHistoryKeepLatest();
    final List<Map<String, Object?>> rows = await db.db.query('note_versions');
    expect(rows.length, 1);
    expect(rows.first['version'], 3);

    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('purgeOrphanTags deletes unreferenced tags', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'maintenance_test_',
    );
    final String dbPath = p.join(tempDir.path, 'tags.db');
    final AppDatabase db = await AppDatabase.open(databasePath: dbPath);
    final MaintenanceService service = MaintenanceService(
      database: db,
      clock: const _FixedClock(1_730_000_000_000),
      ftsUpdater: FtsUpdater(),
    );

    await db.db.insert('tags', <String, Object?>{
      'id': 't1',
      'name': 'keep',
      'created_at': 1,
    });
    await db.db.insert('tags', <String, Object?>{
      'id': 't2',
      'name': 'delete',
      'created_at': 1,
    });
    await db.db.insert('entity_tags', <String, Object?>{
      'entity_type': 'todo',
      'entity_id': 'todo1',
      'tag_id': 't1',
    });

    await service.purgeOrphanTags();
    final List<Map<String, Object?>> rows = await db.db.query(
      'tags',
      orderBy: 'id ASC',
    );
    expect(rows.length, 1);
    expect(rows.first['id'], 't1');

    await db.close();
    await tempDir.delete(recursive: true);
  });
}
