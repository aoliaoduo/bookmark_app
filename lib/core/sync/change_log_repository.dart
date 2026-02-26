import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'sync_models.dart';

class ChangeLogRepository {
  ChangeLogRepository(this._db);

  static const Uuid _uuid = Uuid();
  final Database _db;

  Future<String> append({
    required DatabaseExecutor executor,
    required String entityType,
    required String entityId,
    required SyncOperation operation,
    required int lamport,
    required String deviceId,
    required int createdAt,
    String? payloadJson,
    String? changeId,
  }) async {
    final String id = changeId ?? _uuid.v4();
    await executor.insert('change_log', <String, Object?>{
      'id': id,
      'entity_type': entityType,
      'entity_id': entityId,
      'operation': operation.name,
      'lamport': lamport,
      'device_id': deviceId,
      'payload_json': payloadJson,
      'created_at': createdAt,
      'synced_at': null,
      'retry_count': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return id;
  }

  Future<List<SyncChange>> listPending({int limit = 20}) async {
    final List<Map<String, Object?>> rows = await _db.rawQuery(
      '''
      SELECT id, entity_type, entity_id, operation, lamport, device_id, created_at, payload_json
      FROM change_log
      WHERE synced_at IS NULL
      ORDER BY created_at ASC
      LIMIT ?
      ''',
      <Object?>[limit],
    );
    return rows.map(SyncChange.fromDb).toList(growable: false);
  }

  Future<void> markSynced(
    Iterable<String> changeIds, {
    required int syncedAt,
  }) async {
    final List<String> ids = changeIds.toList(growable: false);
    if (ids.isEmpty) {
      return;
    }
    final String placeholders = List<String>.filled(ids.length, '?').join(',');
    await _db.rawUpdate(
      '''
      UPDATE change_log
      SET synced_at = ?, last_error = NULL
      WHERE id IN ($placeholders)
      ''',
      <Object?>[syncedAt, ...ids],
    );
  }

  Future<void> markFailed(String changeId, String message) async {
    await _db.rawUpdate(
      '''
      UPDATE change_log
      SET retry_count = retry_count + 1, last_error = ?
      WHERE id = ?
      ''',
      <Object?>[message, changeId],
    );
  }

  Future<bool> isRemoteProcessed(String changeId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'processed_changes',
      columns: <String>['change_id'],
      where: 'change_id = ?',
      whereArgs: <Object?>[changeId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> markRemoteProcessed({
    required String changeId,
    required String sourceDeviceId,
    required int appliedAt,
  }) async {
    await _db.insert('processed_changes', <String, Object?>{
      'change_id': changeId,
      'source_device_id': sourceDeviceId,
      'applied_at': appliedAt,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<SyncState> loadSyncState({required int nowMs}) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'sync_state',
      where: 'id = ?',
      whereArgs: const <Object?>[SyncState.singletonId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return SyncState.empty(nowMs: nowMs);
    }
    return SyncState.fromDb(rows.first);
  }

  Future<void> saveSyncState(SyncState state) async {
    await _db.insert('sync_state', <String, Object?>{
      'id': SyncState.singletonId,
      'last_sync_started_at': state.lastSyncStartedAt,
      'last_sync_finished_at': state.lastSyncFinishedAt,
      'next_allowed_sync_at': state.nextAllowedSyncAt,
      'backoff_until': state.backoffUntil,
      'last_error': state.lastError,
      'last_applied_change_id': state.lastAppliedChangeId,
      'last_pushed_change_id': state.lastPushedChangeId,
      'request_window_started_at': state.requestWindowStartedAt,
      'request_count_in_window': state.requestCountInWindow,
      'updated_at': state.updatedAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
