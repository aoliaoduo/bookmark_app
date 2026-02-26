import 'dart:io';

import 'package:code/core/clock/app_clock.dart';
import 'package:code/core/db/app_database.dart';
import 'package:code/core/identity/device_identity_service.dart';
import 'package:code/core/sync/change_log_repository.dart';
import 'package:code/core/sync/remote/sync_remote.dart';
import 'package:code/core/sync/sync_engine.dart';
import 'package:code/core/sync/sync_models.dart';
import 'package:code/core/sync/sync_object_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _MutableClock implements AppClock {
  _MutableClock(this.value);

  int value;

  @override
  int nowMs() => value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('change_log can be pushed and remote changes can be consumed', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'sync_engine_fake_',
    );
    final String dbPath = p.join(tempDir.path, 'sync.db');
    final AppDatabase db = await AppDatabase.open(databasePath: dbPath);
    final ChangeLogRepository changeLog = ChangeLogRepository(db.db);
    final SyncObjectStore objectStore = SyncObjectStore(db);
    final FakeSyncRemote remote = FakeSyncRemote();
    final _MutableClock clock = _MutableClock(1_730_000_000_000);
    final DeviceIdentityService identityService = DeviceIdentityService();
    final SyncEngine engine = SyncEngine(
      changeLogRepository: changeLog,
      objectStore: objectStore,
      remote: remote,
      clock: clock,
      identityService: identityService,
    );

    final String localDeviceId = await identityService.getOrCreateDeviceId(
      db.db,
    );
    await db.db.insert('todos', <String, Object?>{
      'id': 'todo_local_1',
      'title': '本地待办',
      'priority': 1,
      'status': 0,
      'remind_at': null,
      'created_at': clock.nowMs(),
      'updated_at': clock.nowMs(),
      'deleted': 0,
      'lamport': 10,
      'device_id': localDeviceId,
    });
    await changeLog.append(
      executor: db.db,
      entityType: 'todo',
      entityId: 'todo_local_1',
      operation: SyncOperation.upsert,
      lamport: 10,
      deviceId: localDeviceId,
      createdAt: clock.nowMs(),
      changeId: 'local_change_1',
    );

    final SyncRunResult first = await engine.syncOnce(force: true);
    expect(first.pushedCount, 1);
    expect(remote.debugHasChange('local_change_1'), isTrue);
    expect(remote.debugObject('todo', 'todo_local_1'), isNotNull);

    await remote.putObject(
      const SyncObject(
        entityType: 'todo',
        entityId: 'todo_remote_1',
        lamport: 15,
        deviceId: 'remote_a',
        deleted: false,
        content: <String, Object?>{
          'title': '远端待办',
          'priority': 2,
          'status': 0,
          'remind_at': null,
          'created_at': 1_730_000_100_000,
          'updated_at': 1_730_000_100_000,
          'deleted': 0,
          'tags': <String>['远端'],
        },
      ),
    );
    await remote.putChange(
      const SyncChange(
        id: 'remote_change_1',
        entityType: 'todo',
        entityId: 'todo_remote_1',
        operation: SyncOperation.upsert,
        lamport: 15,
        deviceId: 'remote_a',
        createdAt: 1_730_000_100_000,
      ),
    );

    clock.value += 130000;
    final SyncRunResult second = await engine.syncOnce();
    expect(second.appliedCount, greaterThanOrEqualTo(1));

    final List<Map<String, Object?>> rows = await db.db.query(
      'todos',
      where: 'id = ?',
      whereArgs: <Object?>['todo_remote_1'],
      limit: 1,
    );
    expect(rows, isNotEmpty);
    expect(rows.first['title'], '远端待办');

    await db.close();
    await tempDir.delete(recursive: true);
  });
}
