import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../ai/router_decision.dart';
import '../clock/app_clock.dart';
import '../clock/lamport_clock.dart';
import '../db/app_database.dart';
import '../identity/device_identity_service.dart';
import '../search/fts_updater.dart';

class ActionExecutor {
  ActionExecutor({
    required this.database,
    required this.identityService,
    required this.lamportClock,
    required this.clock,
    required this.ftsUpdater,
  });

  static const Uuid _uuid = Uuid();

  final AppDatabase database;
  final DeviceIdentityService identityService;
  final LamportClock lamportClock;
  final AppClock clock;
  final FtsUpdater ftsUpdater;

  Future<void> execute(
    RouterDecision decision, {
    required String rawInput,
  }) async {
    switch (decision.action) {
      case 'create_todo':
        return _createTodo(decision.payload);
      case 'create_note':
        return _createNote(decision.payload, rawInput: rawInput);
      case 'create_bookmark':
        return _createBookmark(decision.payload);
      default:
        throw Exception('M2 暂不支持 action: ${decision.action}');
    }
  }

  Future<void> _createTodo(Map<String, Object?> payload) async {
    await database.db.transaction((txn) async {
      final String deviceId = await identityService.getOrCreateDeviceId(txn);
      final int now = clock.nowMs();
      final int lamport = await lamportClock.next(txn);
      final String id = _uuid.v4();
      final Batch batch = txn.batch();

      batch.insert('todos', {
        'id': id,
        'title': payload['title'] as String,
        'priority': _priorityCode((payload['priority'] as String?) ?? 'medium'),
        'status': TodoStatusCode.open,
        'remind_at': payload['remind_at'],
        'created_at': now,
        'updated_at': now,
        'deleted': 0,
        'lamport': lamport,
        'device_id': deviceId,
      });

      final List<String> tags = _normalizeTags(payload['tags']);
      await _bindTags(
        txn: txn,
        batch: batch,
        entityType: 'todo',
        entityId: id,
        tags: tags,
        now: now,
      );

      await batch.commit(noResult: true);
      await ftsUpdater.upsertTodo(txn, id);
    });
  }

  Future<void> _createNote(
    Map<String, Object?> payload, {
    required String rawInput,
  }) async {
    await database.db.transaction((txn) async {
      final String deviceId = await identityService.getOrCreateDeviceId(txn);
      final int now = clock.nowMs();
      final int lamport = await lamportClock.next(txn);
      final String id = _uuid.v4();
      final Batch batch = txn.batch();

      batch.insert('notes', {
        'id': id,
        'title': payload['title'] as String,
        'raw_text': rawInput,
        'latest_version': 1,
        'created_at': now,
        'updated_at': now,
        'deleted': 0,
        'lamport': lamport,
        'device_id': deviceId,
      });

      batch.insert('note_versions', {
        'note_id': id,
        'version': 1,
        'organized_md': payload['organized_md'] as String,
        'created_at': now,
      });

      final List<String> tags = _normalizeTags(payload['tags']);
      await _bindTags(
        txn: txn,
        batch: batch,
        entityType: 'note',
        entityId: id,
        tags: tags,
        now: now,
      );

      await batch.commit(noResult: true);
      await ftsUpdater.upsertNote(txn, id);
    });
  }

  Future<void> _createBookmark(Map<String, Object?> payload) async {
    await database.db.transaction((txn) async {
      final String deviceId = await identityService.getOrCreateDeviceId(txn);
      final int now = clock.nowMs();
      final int lamport = await lamportClock.next(txn);
      final String id = _uuid.v4();

      await txn.insert('bookmarks', {
        'id': id,
        'url': payload['url'] as String,
        'title': '',
        'last_fetched_at': null,
        'created_at': now,
        'updated_at': now,
        'deleted': 0,
        'lamport': lamport,
        'device_id': deviceId,
      });
      await ftsUpdater.upsertBookmark(txn, id);
    });
  }

  Future<void> _bindTags({
    required Transaction txn,
    required Batch batch,
    required String entityType,
    required String entityId,
    required List<String> tags,
    required int now,
  }) async {
    for (final String tag in tags) {
      final List<Map<String, Object?>> rows = await txn.query(
        'tags',
        columns: ['id'],
        where: 'name = ?',
        whereArgs: <Object?>[tag],
        limit: 1,
      );

      String tagId;
      if (rows.isEmpty) {
        tagId = _uuid.v4();
        batch.insert('tags', {'id': tagId, 'name': tag, 'created_at': now});
      } else {
        tagId = rows.first['id']! as String;
      }

      batch.insert('entity_tags', {
        'entity_type': entityType,
        'entity_id': entityId,
        'tag_id': tagId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  int _priorityCode(String value) {
    return switch (value) {
      'high' => TodoPriorityCode.high,
      'low' => TodoPriorityCode.low,
      _ => TodoPriorityCode.medium,
    };
  }

  List<String> _normalizeTags(Object? rawTags) {
    if (rawTags is! List<Object?>) {
      return const <String>[];
    }

    final Set<String> result = <String>{};
    for (final Object? tag in rawTags) {
      if (tag is! String) {
        continue;
      }
      final String normalized = tag.trim();
      if (normalized.isNotEmpty) {
        result.add(normalized);
      }
    }
    return result.toList(growable: false);
  }
}
