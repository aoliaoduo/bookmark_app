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

class _DbFixture {
  const _DbFixture({
    required this.appDatabase,
    required this.tempDir,
    required this.repository,
  });

  final AppDatabase appDatabase;
  final Directory tempDir;
  final LibraryRepository repository;
}

Future<_DbFixture> _prepareDb({required String todoTitle}) async {
  final Directory tempDir = await Directory.systemTemp.createTemp(
    'detail_test_',
  );
  final String dbPath = p.join(tempDir.path, 'detail.db');
  final AppDatabase appDatabase = await AppDatabase.open(databasePath: dbPath);
  final int now = DateTime.now().millisecondsSinceEpoch;

  await appDatabase.db.insert('todos', <String, Object?>{
    'id': 'todo_1',
    'title': todoTitle,
    'priority': 1,
    'status': 0,
    'remind_at': null,
    'created_at': now,
    'updated_at': now,
    'deleted': 0,
    'lamport': 10,
    'device_id': 'test_device',
  });
  await appDatabase.db.insert('kv', <String, Object?>{
    'key': 'lamport',
    'value': '10',
  });
  await appDatabase.db.insert('kv', <String, Object?>{
    'key': 'device_id',
    'value': 'test_device',
  });

  final LibraryRepository repository = LibraryRepository(
    database: appDatabase,
    identityService: DeviceIdentityService(),
    lamportClock: LamportClock(),
    clock: SystemClock(),
    ftsUpdater: FtsUpdater(),
    changeLogRepository: ChangeLogRepository(appDatabase.db),
  );

  return _DbFixture(
    appDatabase: appDatabase,
    tempDir: tempDir,
    repository: repository,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('detail_edit_cancel_test', () async {
    final _DbFixture fixture = await _prepareDb(todoTitle: 'origin_title');
    final AppDatabase appDatabase = fixture.appDatabase;

    // Cancel path: user edits draft but does not trigger repository write.
    final TodoDetail? detail = await fixture.repository.getTodoDetail('todo_1');
    expect(detail, isNotNull);
    final String draftTitle = 'changed_title';
    expect(draftTitle, isNot(equals(detail!.title)));

    final List<Map<String, Object?>> rows = await appDatabase.db.query(
      'todos',
      columns: <String>['title'],
      where: 'id = ?',
      whereArgs: <Object?>['todo_1'],
      limit: 1,
    );

    expect(rows.first['title'], 'origin_title');

    await appDatabase.close();
    await fixture.tempDir.delete(recursive: true);
  });

  test('detail_edit_save_updates_test', () async {
    final _DbFixture fixture = await _prepareDb(todoTitle: 'before_title');
    final AppDatabase appDatabase = fixture.appDatabase;

    final List<Map<String, Object?>> beforeRows = await appDatabase.db.query(
      'todos',
      columns: <String>['lamport', 'updated_at'],
      where: 'id = ?',
      whereArgs: <Object?>['todo_1'],
      limit: 1,
    );
    final int beforeLamport = (beforeRows.first['lamport'] as num).toInt();
    final int beforeUpdatedAt = (beforeRows.first['updated_at'] as num).toInt();

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await fixture.repository.updateTodoDetail(
      todoId: 'todo_1',
      title: 'after_title_unique',
      priority: 1,
      status: TodoStatusCode.open,
      remindAt: null,
      tags: const <String>['updated'],
    );

    final List<Map<String, Object?>> afterRows = await appDatabase.db.query(
      'todos',
      columns: <String>['title', 'lamport', 'updated_at'],
      where: 'id = ?',
      whereArgs: <Object?>['todo_1'],
      limit: 1,
    );

    expect(afterRows.first['title'], 'after_title_unique');
    expect(
      (afterRows.first['lamport'] as num).toInt(),
      greaterThan(beforeLamport),
    );
    expect(
      (afterRows.first['updated_at'] as num).toInt(),
      greaterThan(beforeUpdatedAt),
    );

    final List<Map<String, Object?>> ftsRows = await appDatabase.db.rawQuery(
      "SELECT entity_id FROM search_fts WHERE search_fts MATCH 'after_title_unique' LIMIT 1;",
    );
    expect(ftsRows.isNotEmpty, isTrue);
    expect(ftsRows.first['entity_id'], 'todo_1');

    await appDatabase.close();
    await fixture.tempDir.delete(recursive: true);
  });
}
