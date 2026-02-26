import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import 'lww.dart';
import 'sync_models.dart';

class SyncObjectStore {
  SyncObjectStore(this.database);

  static const Uuid _uuid = Uuid();
  final AppDatabase database;

  Future<SyncObject?> buildObjectForChange(SyncChange change) async {
    switch (change.entityType) {
      case 'todo':
        return _buildTodo(change);
      case 'note':
        return _buildNote(change);
      case 'bookmark':
        return _buildBookmark(change);
      case 'tag':
        return _buildTag(change);
      case 'secret':
        return _buildSecret(change);
      default:
        return null;
    }
  }

  Future<void> applyRemoteObject(SyncObject remoteObject) async {
    switch (remoteObject.entityType) {
      case 'todo':
        await _applyTodo(remoteObject);
        return;
      case 'note':
        await _applyNote(remoteObject);
        return;
      case 'bookmark':
        await _applyBookmark(remoteObject);
        return;
      case 'tag':
        await _applyTag(remoteObject);
        return;
      case 'secret':
        await _applySecret(remoteObject);
        return;
      default:
        return;
    }
  }

  Future<SyncObject?> _buildTodo(SyncChange change) async {
    final List<Map<String, Object?>> rows = await database.db.query(
      'todos',
      where: 'id = ?',
      whereArgs: <Object?>[change.entityId],
      limit: 1,
    );
    if (rows.isEmpty) {
      if (change.operation != SyncOperation.delete) {
        return null;
      }
      return SyncObject(
        entityType: 'todo',
        entityId: change.entityId,
        lamport: change.lamport,
        deviceId: change.deviceId,
        deleted: true,
        content: <String, Object?>{},
      );
    }
    final Map<String, Object?> row = rows.first;
    final List<String> tags = await _loadTags(
      entityType: 'todo',
      entityId: change.entityId,
    );
    return SyncObject(
      entityType: 'todo',
      entityId: change.entityId,
      lamport: change.lamport,
      deviceId: change.deviceId,
      deleted:
          change.operation == SyncOperation.delete ||
          ((row['deleted'] as num?)?.toInt() ?? 0) != 0,
      content: <String, Object?>{
        'title': row['title'],
        'priority': row['priority'],
        'status': row['status'],
        'remind_at': row['remind_at'],
        'created_at': row['created_at'],
        'updated_at': row['updated_at'],
        'deleted': row['deleted'],
        'tags': tags,
      },
    );
  }

  Future<SyncObject?> _buildNote(SyncChange change) async {
    final List<Map<String, Object?>> rows = await database.db.query(
      'notes',
      where: 'id = ?',
      whereArgs: <Object?>[change.entityId],
      limit: 1,
    );
    if (rows.isEmpty) {
      if (change.operation != SyncOperation.delete) {
        return null;
      }
      return SyncObject(
        entityType: 'note',
        entityId: change.entityId,
        lamport: change.lamport,
        deviceId: change.deviceId,
        deleted: true,
        content: const <String, Object?>{},
      );
    }
    final Map<String, Object?> row = rows.first;
    final int latestVersion = ((row['latest_version'] as num?)?.toInt() ?? 1);
    final List<Map<String, Object?>> versionRows = await database.db.query(
      'note_versions',
      columns: <String>['organized_md'],
      where: 'note_id = ? AND version = ?',
      whereArgs: <Object?>[change.entityId, latestVersion],
      limit: 1,
    );
    final String organizedMd =
        (versionRows.firstOrNull?['organized_md'] as String?) ?? '';
    final List<String> tags = await _loadTags(
      entityType: 'note',
      entityId: change.entityId,
    );
    return SyncObject(
      entityType: 'note',
      entityId: change.entityId,
      lamport: change.lamport,
      deviceId: change.deviceId,
      deleted:
          change.operation == SyncOperation.delete ||
          ((row['deleted'] as num?)?.toInt() ?? 0) != 0,
      content: <String, Object?>{
        'title': row['title'],
        'raw_text': row['raw_text'],
        'latest_version': latestVersion,
        'organized_md': organizedMd,
        'created_at': row['created_at'],
        'updated_at': row['updated_at'],
        'deleted': row['deleted'],
        'tags': tags,
      },
    );
  }

  Future<SyncObject?> _buildBookmark(SyncChange change) async {
    final List<Map<String, Object?>> rows = await database.db.query(
      'bookmarks',
      where: 'id = ?',
      whereArgs: <Object?>[change.entityId],
      limit: 1,
    );
    if (rows.isEmpty) {
      if (change.operation != SyncOperation.delete) {
        return null;
      }
      return SyncObject(
        entityType: 'bookmark',
        entityId: change.entityId,
        lamport: change.lamport,
        deviceId: change.deviceId,
        deleted: true,
        content: const <String, Object?>{},
      );
    }
    final Map<String, Object?> row = rows.first;
    return SyncObject(
      entityType: 'bookmark',
      entityId: change.entityId,
      lamport: change.lamport,
      deviceId: change.deviceId,
      deleted:
          change.operation == SyncOperation.delete ||
          ((row['deleted'] as num?)?.toInt() ?? 0) != 0,
      content: <String, Object?>{
        'url': row['url'],
        'title': row['title'],
        'last_fetched_at': row['last_fetched_at'],
        'created_at': row['created_at'],
        'updated_at': row['updated_at'],
        'deleted': row['deleted'],
      },
    );
  }

  Future<SyncObject?> _buildTag(SyncChange change) async {
    final List<Map<String, Object?>> rows = await database.db.query(
      'tags',
      where: 'id = ?',
      whereArgs: <Object?>[change.entityId],
      limit: 1,
    );
    if (rows.isEmpty) {
      if (change.operation != SyncOperation.delete) {
        return null;
      }
      return SyncObject(
        entityType: 'tag',
        entityId: change.entityId,
        lamport: change.lamport,
        deviceId: change.deviceId,
        deleted: true,
        content: const <String, Object?>{},
      );
    }
    final Map<String, Object?> row = rows.first;
    return SyncObject(
      entityType: 'tag',
      entityId: change.entityId,
      lamport: change.lamport,
      deviceId: change.deviceId,
      deleted: change.operation == SyncOperation.delete,
      content: <String, Object?>{
        'name': row['name'],
        'created_at': row['created_at'],
      },
    );
  }

  Future<SyncObject?> _buildSecret(SyncChange change) async {
    final List<Map<String, Object?>> rows = await database.db.query(
      'kv',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: const <Object?>['ai_provider_json'],
      limit: 1,
    );
    if (rows.isEmpty && change.operation != SyncOperation.delete) {
      return null;
    }
    final String? value = rows.firstOrNull?['value'] as String?;
    return SyncObject(
      entityType: 'secret',
      entityId: change.entityId,
      lamport: change.lamport,
      deviceId: change.deviceId,
      deleted: change.operation == SyncOperation.delete,
      content: <String, Object?>{'value': value ?? ''},
    );
  }

  Future<void> _applyTodo(SyncObject remote) async {
    await database.db.transaction((txn) async {
      final List<Map<String, Object?>> localRows = await txn.query(
        'todos',
        columns: <String>['lamport', 'device_id'],
        where: 'id = ?',
        whereArgs: <Object?>[remote.entityId],
        limit: 1,
      );
      if (localRows.isNotEmpty) {
        final Map<String, Object?> local = localRows.first;
        final LwwDecision decision = compareLww(
          localLamport: (local['lamport'] as num).toInt(),
          localDeviceId: local['device_id']! as String,
          remoteLamport: remote.lamport,
          remoteDeviceId: remote.deviceId,
        );
        if (decision == LwwDecision.keepLocal) {
          return;
        }
      }
      final Map<String, Object?> c = remote.content;
      await txn.insert('todos', <String, Object?>{
        'id': remote.entityId,
        'title': c['title'] ?? '',
        'priority': (c['priority'] as num?)?.toInt() ?? TodoPriorityCode.medium,
        'status': (c['status'] as num?)?.toInt() ?? TodoStatusCode.open,
        'remind_at': c['remind_at'],
        'created_at': (c['created_at'] as num?)?.toInt() ?? 0,
        'updated_at': (c['updated_at'] as num?)?.toInt() ?? 0,
        'deleted': remote.deleted ? 1 : ((c['deleted'] as num?)?.toInt() ?? 0),
        'lamport': remote.lamport,
        'device_id': remote.deviceId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await _replaceEntityTags(
        txn: txn,
        entityType: 'todo',
        entityId: remote.entityId,
        tags: (c['tags'] as List<Object?>? ?? const <Object?>[])
            .whereType<String>()
            .toList(growable: false),
        createdAt: (c['updated_at'] as num?)?.toInt() ?? 0,
      );
    });
  }

  Future<void> _applyNote(SyncObject remote) async {
    await database.db.transaction((txn) async {
      final List<Map<String, Object?>> localRows = await txn.query(
        'notes',
        columns: <String>['lamport', 'device_id'],
        where: 'id = ?',
        whereArgs: <Object?>[remote.entityId],
        limit: 1,
      );
      if (localRows.isNotEmpty) {
        final Map<String, Object?> local = localRows.first;
        final LwwDecision decision = compareLww(
          localLamport: (local['lamport'] as num).toInt(),
          localDeviceId: local['device_id']! as String,
          remoteLamport: remote.lamport,
          remoteDeviceId: remote.deviceId,
        );
        if (decision == LwwDecision.keepLocal) {
          return;
        }
      }

      final Map<String, Object?> c = remote.content;
      final int latestVersion = ((c['latest_version'] as num?)?.toInt() ?? 1);
      final int updatedAt = (c['updated_at'] as num?)?.toInt() ?? 0;
      await txn.insert('notes', <String, Object?>{
        'id': remote.entityId,
        'title': c['title'] ?? '',
        'raw_text': c['raw_text'] ?? '',
        'latest_version': latestVersion,
        'created_at': (c['created_at'] as num?)?.toInt() ?? 0,
        'updated_at': updatedAt,
        'deleted': remote.deleted ? 1 : ((c['deleted'] as num?)?.toInt() ?? 0),
        'lamport': remote.lamport,
        'device_id': remote.deviceId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('note_versions', <String, Object?>{
        'note_id': remote.entityId,
        'version': latestVersion,
        'organized_md': c['organized_md'] ?? '',
        'created_at': updatedAt,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _replaceEntityTags(
        txn: txn,
        entityType: 'note',
        entityId: remote.entityId,
        tags: (c['tags'] as List<Object?>? ?? const <Object?>[])
            .whereType<String>()
            .toList(growable: false),
        createdAt: updatedAt,
      );
    });
  }

  Future<void> _applyBookmark(SyncObject remote) async {
    await database.db.transaction((txn) async {
      final List<Map<String, Object?>> localRows = await txn.query(
        'bookmarks',
        columns: <String>['lamport', 'device_id'],
        where: 'id = ?',
        whereArgs: <Object?>[remote.entityId],
        limit: 1,
      );
      if (localRows.isNotEmpty) {
        final Map<String, Object?> local = localRows.first;
        final LwwDecision decision = compareLww(
          localLamport: (local['lamport'] as num).toInt(),
          localDeviceId: local['device_id']! as String,
          remoteLamport: remote.lamport,
          remoteDeviceId: remote.deviceId,
        );
        if (decision == LwwDecision.keepLocal) {
          return;
        }
      }
      final Map<String, Object?> c = remote.content;
      await txn.insert('bookmarks', <String, Object?>{
        'id': remote.entityId,
        'url': c['url'] ?? '',
        'title': c['title'],
        'last_fetched_at': c['last_fetched_at'],
        'created_at': (c['created_at'] as num?)?.toInt() ?? 0,
        'updated_at': (c['updated_at'] as num?)?.toInt() ?? 0,
        'deleted': remote.deleted ? 1 : ((c['deleted'] as num?)?.toInt() ?? 0),
        'lamport': remote.lamport,
        'device_id': remote.deviceId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> _applyTag(SyncObject remote) async {
    if (remote.deleted) {
      await database.db.delete(
        'tags',
        where: 'id = ?',
        whereArgs: <Object?>[remote.entityId],
      );
      await database.db.delete(
        'entity_tags',
        where: 'tag_id = ?',
        whereArgs: <Object?>[remote.entityId],
      );
      return;
    }
    final Map<String, Object?> c = remote.content;
    await database.db.insert('tags', <String, Object?>{
      'id': remote.entityId,
      'name': c['name'] ?? '',
      'created_at': (c['created_at'] as num?)?.toInt() ?? 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _applySecret(SyncObject remote) async {
    if (remote.entityId != 'api_provider') {
      return;
    }
    if (remote.deleted) {
      await database.db.delete(
        'kv',
        where: 'key = ?',
        whereArgs: const <Object?>['ai_provider_json'],
      );
      return;
    }
    final String value = (remote.content['value'] as String?) ?? '';
    await database.db.insert('kv', <String, Object?>{
      'key': 'ai_provider_json',
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await database.db.insert('kv', <String, Object?>{
      'key': 'secret_ai_provider_lamport',
      'value': jsonEncode(<String, Object?>{
        'lamport': remote.lamport,
        'device_id': remote.deviceId,
      }),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<String>> _loadTags({
    required String entityType,
    required String entityId,
  }) async {
    final List<Map<String, Object?>> rows = await database.db.rawQuery(
      '''
      SELECT t.name
      FROM entity_tags et
      JOIN tags t ON t.id = et.tag_id
      WHERE et.entity_type = ? AND et.entity_id = ?
      ORDER BY t.name ASC
      ''',
      <Object?>[entityType, entityId],
    );
    return rows
        .map((Map<String, Object?> row) => row['name']! as String)
        .toList(growable: false);
  }

  Future<void> _replaceEntityTags({
    required Transaction txn,
    required String entityType,
    required String entityId,
    required List<String> tags,
    required int createdAt,
  }) async {
    await txn.delete(
      'entity_tags',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: <Object?>[entityType, entityId],
    );
    for (final String tag in tags) {
      final List<Map<String, Object?>> rows = await txn.query(
        'tags',
        columns: <String>['id'],
        where: 'name = ?',
        whereArgs: <Object?>[tag],
        limit: 1,
      );
      String tagId;
      if (rows.isEmpty) {
        tagId = _uuid.v4();
        await txn.insert('tags', <String, Object?>{
          'id': tagId,
          'name': tag,
          'created_at': createdAt,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      } else {
        tagId = rows.first['id']! as String;
      }
      await txn.insert('entity_tags', <String, Object?>{
        'entity_type': entityType,
        'entity_id': entityId,
        'tag_id': tagId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }
}
