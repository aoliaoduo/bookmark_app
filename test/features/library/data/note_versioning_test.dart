import 'dart:io';

import 'package:code/core/clock/app_clock.dart';
import 'package:code/core/clock/lamport_clock.dart';
import 'package:code/core/db/app_database.dart';
import 'package:code/core/identity/device_identity_service.dart';
import 'package:code/core/search/fts_updater.dart';
import 'package:code/core/sync/change_log_repository.dart';
import 'package:code/features/library/data/library_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FixedClock implements AppClock {
  const _FixedClock(this.start);

  final int start;

  @override
  int nowMs() => start;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'note versioning increments latest version and keeps old version',
    () async {
      final Directory dir = await Directory.systemTemp.createTemp('note_ver_');
      final String dbPath = p.join(dir.path, 'note.db');

      final AppDatabase db = await AppDatabase.open(databasePath: dbPath);
      final repo = LibraryRepository(
        database: db,
        identityService: DeviceIdentityService(),
        lamportClock: LamportClock(),
        clock: const _FixedClock(1730000000000),
        ftsUpdater: FtsUpdater(),
        changeLogRepository: ChangeLogRepository(db.db),
      );

      await db.db.insert('notes', {
        'id': 'n1',
        'title': '测试笔记',
        'raw_text': '原文',
        'latest_version': 1,
        'created_at': 1,
        'updated_at': 1,
        'deleted': 0,
        'lamport': 1,
        'device_id': 'd1',
      });
      await db.db.insert('note_versions', {
        'note_id': 'n1',
        'version': 1,
        'organized_md': '# v1',
        'created_at': 1,
      });

      await repo.appendNoteVersion(noteId: 'n1', organizedMd: '# v2');

      final notesRows = await db.db.query(
        'notes',
        where: 'id = ?',
        whereArgs: ['n1'],
      );
      expect(notesRows.first['latest_version'], 2);

      final versionRows = await db.db.rawQuery(
        'SELECT version FROM note_versions WHERE note_id = ? ORDER BY version ASC;',
        ['n1'],
      );
      expect(versionRows.length, 2);
      expect(versionRows.first['version'], 1);
      expect(versionRows.last['version'], 2);

      await db.close();
      await dir.delete(recursive: true);
    },
  );

  test('prune note versions keeps latest N', () async {
    final Directory dir = await Directory.systemTemp.createTemp('note_prune_');
    final String dbPath = p.join(dir.path, 'note.db');

    final AppDatabase db = await AppDatabase.open(databasePath: dbPath);
    final repo = LibraryRepository(
      database: db,
      identityService: DeviceIdentityService(),
      lamportClock: LamportClock(),
      clock: const _FixedClock(1730000000000),
      ftsUpdater: FtsUpdater(),
      changeLogRepository: ChangeLogRepository(db.db),
    );

    await db.db.insert('notes', {
      'id': 'n2',
      'title': '测试裁剪',
      'raw_text': '原文',
      'latest_version': 1,
      'created_at': 1,
      'updated_at': 1,
      'deleted': 0,
      'lamport': 1,
      'device_id': 'd1',
    });

    for (int i = 1; i <= 6; i++) {
      await db.db.insert('note_versions', {
        'note_id': 'n2',
        'version': i,
        'organized_md': '# v$i',
        'created_at': i,
      });
    }
    await db.db.update(
      'notes',
      {'latest_version': 6},
      where: 'id = ?',
      whereArgs: ['n2'],
    );

    await repo.pruneNoteVersions(noteId: 'n2', keepLatest: 3);

    final List<Map<String, Object?>> rows = await db.db.rawQuery(
      'SELECT version FROM note_versions WHERE note_id = ? ORDER BY version ASC;',
      ['n2'],
    );
    expect(rows.length, 3);
    expect(rows.first['version'], 4);
    expect(rows.last['version'], 6);

    await db.close();
    await dir.delete(recursive: true);
  });
}
