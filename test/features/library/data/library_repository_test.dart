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
  const _FixedClock(this.value);

  final int value;

  @override
  int nowMs() => value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('listTodos paginates with pageSize=50', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'repo_test_',
    );
    final String dbPath = p.join(tempDir.path, 'repo.db');

    final AppDatabase appDatabase = await AppDatabase.open(
      databasePath: dbPath,
    );
    final LibraryRepository repository = LibraryRepository(
      database: appDatabase,
      identityService: DeviceIdentityService(),
      lamportClock: LamportClock(),
      clock: const _FixedClock(1730000000000),
      ftsUpdater: FtsUpdater(),
      changeLogRepository: ChangeLogRepository(appDatabase.db),
    );

    await repository.clearLibraryData();
    await repository.seedDebugData(
      todoCount: 120,
      noteCount: 0,
      bookmarkCount: 0,
    );

    final PagedResult<TodoListItem> page0 = await repository.listTodos(
      page: 0,
      pageSize: 50,
      includeDone: true,
    );
    final PagedResult<TodoListItem> page1 = await repository.listTodos(
      page: 1,
      pageSize: 50,
      includeDone: true,
    );
    final PagedResult<TodoListItem> page2 = await repository.listTodos(
      page: 2,
      pageSize: 50,
      includeDone: true,
    );

    expect(page0.items.length, 50);
    expect(page1.items.length, 50);
    expect(page2.items.length, 20);

    expect(page0.hasMore, isTrue);
    expect(page1.hasMore, isTrue);
    expect(page2.hasMore, isFalse);

    await appDatabase.close();
    await tempDir.delete(recursive: true);
  });

  test('seed creates note_versions and clear keeps kv', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'repo_test_',
    );
    final String dbPath = p.join(tempDir.path, 'repo.db');

    final AppDatabase appDatabase = await AppDatabase.open(
      databasePath: dbPath,
    );
    final LibraryRepository repository = LibraryRepository(
      database: appDatabase,
      identityService: DeviceIdentityService(),
      lamportClock: LamportClock(),
      clock: const _FixedClock(1730000000000),
      ftsUpdater: FtsUpdater(),
      changeLogRepository: ChangeLogRepository(appDatabase.db),
    );

    await repository.clearLibraryData();
    await repository.seedDebugData(
      todoCount: 10,
      noteCount: 5,
      bookmarkCount: 2,
    );

    final List<Map<String, Object?>> noteVersionRows = await appDatabase.db
        .rawQuery('SELECT COUNT(*) AS c FROM note_versions;');
    expect(noteVersionRows.first['c'], 5);

    await repository.clearLibraryData();

    final List<Map<String, Object?>> kvRows = await appDatabase.db.rawQuery(
      "SELECT key FROM kv WHERE key IN ('device_id','lamport');",
    );
    expect(kvRows.length, 2);

    await appDatabase.close();
    await tempDir.delete(recursive: true);
  });

  test('listTodos supports done/remind filters', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'repo_test_',
    );
    final String dbPath = p.join(tempDir.path, 'repo.db');

    final AppDatabase appDatabase = await AppDatabase.open(
      databasePath: dbPath,
    );
    final LibraryRepository repository = LibraryRepository(
      database: appDatabase,
      identityService: DeviceIdentityService(),
      lamportClock: LamportClock(),
      clock: const _FixedClock(1730000000000),
      ftsUpdater: FtsUpdater(),
      changeLogRepository: ChangeLogRepository(appDatabase.db),
    );

    await repository.clearLibraryData();
    final int now = 1730000000000;
    await appDatabase.db.insert('todos', <String, Object?>{
      'id': 'todo_open_none',
      'title': 'open none',
      'priority': TodoPriorityCode.medium,
      'status': TodoStatusCode.open,
      'remind_at': null,
      'created_at': now,
      'updated_at': now,
      'deleted': 0,
      'lamport': 1,
      'device_id': 'test_device',
    });
    await appDatabase.db.insert('todos', <String, Object?>{
      'id': 'todo_open_with',
      'title': 'open with remind',
      'priority': TodoPriorityCode.medium,
      'status': TodoStatusCode.open,
      'remind_at': now + 60000,
      'created_at': now - 1,
      'updated_at': now - 1,
      'deleted': 0,
      'lamport': 2,
      'device_id': 'test_device',
    });
    await appDatabase.db.insert('todos', <String, Object?>{
      'id': 'todo_done_with',
      'title': 'done with remind',
      'priority': TodoPriorityCode.medium,
      'status': TodoStatusCode.done,
      'remind_at': now + 120000,
      'created_at': now - 2,
      'updated_at': now - 2,
      'deleted': 0,
      'lamport': 3,
      'device_id': 'test_device',
    });

    final PagedResult<TodoListItem> openOnly = await repository.listTodos(
      page: 0,
      pageSize: 20,
    );
    final PagedResult<TodoListItem> withRemind = await repository.listTodos(
      page: 0,
      pageSize: 20,
      remindFilter: TodoRemindFilter.withRemind,
    );
    final PagedResult<TodoListItem> withoutRemind = await repository.listTodos(
      page: 0,
      pageSize: 20,
      remindFilter: TodoRemindFilter.withoutRemind,
    );
    final PagedResult<TodoListItem> includeDoneAndWithRemind = await repository
        .listTodos(
          page: 0,
          pageSize: 20,
          includeDone: true,
          remindFilter: TodoRemindFilter.withRemind,
        );

    expect(openOnly.items.length, 2);
    expect(withRemind.items.length, 1);
    expect(withoutRemind.items.length, 1);
    expect(includeDoneAndWithRemind.items.length, 2);

    await appDatabase.close();
    await tempDir.delete(recursive: true);
  });
}
