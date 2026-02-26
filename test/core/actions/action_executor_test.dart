import 'dart:io';

import 'package:code/core/actions/action_executor.dart';
import 'package:code/core/ai/router_decision.dart';
import 'package:code/core/clock/app_clock.dart';
import 'package:code/core/clock/lamport_clock.dart';
import 'package:code/core/db/app_database.dart';
import 'package:code/core/identity/device_identity_service.dart';
import 'package:code/core/search/fts_updater.dart';
import 'package:code/core/sync/change_log_repository.dart';
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

  test('ActionExecutor create_todo persists fields', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'act_test_',
    );
    final String dbPath = p.join(tempDir.path, 'act.db');

    final AppDatabase db = await AppDatabase.open(databasePath: dbPath);
    final ActionExecutor executor = ActionExecutor(
      database: db,
      identityService: DeviceIdentityService(),
      lamportClock: LamportClock(),
      clock: const _FixedClock(1730000000000),
      ftsUpdater: FtsUpdater(),
      changeLogRepository: ChangeLogRepository(db.db),
    );

    await executor.execute(
      const RouterDecision(
        action: 'create_todo',
        confidence: 0.9,
        payload: {
          'title': '测试待办',
          'priority': 'high',
          'tags': ['工作'],
        },
      ),
      rawInput: '测试待办',
    );

    final rows = await db.db.rawQuery('SELECT * FROM todos LIMIT 1;');
    expect(rows.length, 1);
    final row = rows.first;
    expect(row['title'], '测试待办');
    expect(row['priority'], 2);
    expect(row['status'], 0);
    expect((row['lamport'] as int) > 0, isTrue);
    expect((row['device_id'] as String).isNotEmpty, isTrue);

    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('ActionExecutor create_note persists note and version', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'act_test_',
    );
    final String dbPath = p.join(tempDir.path, 'act2.db');

    final AppDatabase db = await AppDatabase.open(databasePath: dbPath);
    final ActionExecutor executor = ActionExecutor(
      database: db,
      identityService: DeviceIdentityService(),
      lamportClock: LamportClock(),
      clock: const _FixedClock(1730000001000),
      ftsUpdater: FtsUpdater(),
      changeLogRepository: ChangeLogRepository(db.db),
    );

    await executor.execute(
      const RouterDecision(
        action: 'create_note',
        confidence: 0.88,
        payload: {
          'title': '会议纪要',
          'tags': ['工作', '会议'],
          'organized_md': '# 会议纪要\n- 待办1',
        },
      ),
      rawInput: '原始会议速记',
    );

    final noteRows = await db.db.rawQuery('SELECT * FROM notes LIMIT 1;');
    expect(noteRows.length, 1);
    final noteId = noteRows.first['id'] as String;
    expect(noteRows.first['raw_text'], '原始会议速记');

    final versionRows = await db.db.rawQuery(
      'SELECT * FROM note_versions WHERE note_id = ? LIMIT 1;',
      [noteId],
    );
    expect(versionRows.length, 1);
    expect(versionRows.first['version'], 1);

    await db.close();
    await tempDir.delete(recursive: true);
  });
}
