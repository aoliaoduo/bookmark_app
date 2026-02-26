import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/bookmark/bookmark_title_fetcher.dart';
import '../../../core/clock/app_clock.dart';
import '../../../core/clock/lamport_clock.dart';
import '../../../core/db/app_database.dart';
import '../../../core/identity/device_identity_service.dart';
import '../../../core/search/fts_updater.dart';
import '../../../core/sync/change_log_repository.dart';
import '../../../core/sync/sync_models.dart';

class PagedResult<T> {
  const PagedResult({required this.items, required this.hasMore});

  final List<T> items;
  final bool hasMore;
}

class TodoListItem {
  const TodoListItem({
    required this.id,
    required this.title,
    required this.priority,
    required this.status,
    required this.tagCount,
  });

  final String id;
  final String title;
  final int priority;
  final int status;
  final int tagCount;
}

class TodoDetail {
  const TodoDetail({
    required this.id,
    required this.title,
    required this.priority,
    required this.status,
    required this.remindAt,
    required this.tags,
  });

  final String id;
  final String title;
  final int priority;
  final int status;
  final int? remindAt;
  final List<String> tags;
}

class NoteListItem {
  const NoteListItem({
    required this.id,
    required this.title,
    required this.latestVersion,
  });

  final String id;
  final String title;
  final int latestVersion;
}

class NoteDetail {
  const NoteDetail({
    required this.id,
    required this.title,
    required this.rawText,
    required this.latestVersion,
    required this.organizedMd,
  });

  final String id;
  final String title;
  final String rawText;
  final int latestVersion;
  final String organizedMd;
}

class NoteVersionItem {
  const NoteVersionItem({required this.version, required this.createdAt});

  final int version;
  final int createdAt;
}

class BookmarkListItem {
  const BookmarkListItem({
    required this.id,
    required this.title,
    required this.url,
  });

  final String id;
  final String title;
  final String url;
}

class BookmarkDetail {
  const BookmarkDetail({
    required this.id,
    required this.title,
    required this.url,
    required this.lastFetchedAt,
    required this.tags,
  });

  final String id;
  final String title;
  final String url;
  final int? lastFetchedAt;
  final List<String> tags;
}

class LibraryRepository {
  LibraryRepository({
    required this.database,
    required this.identityService,
    required this.lamportClock,
    required this.clock,
    required this.ftsUpdater,
    required this.changeLogRepository,
  });

  static const int defaultPageSize = 50;
  static const Uuid _uuid = Uuid();

  final AppDatabase database;
  final DeviceIdentityService identityService;
  final LamportClock lamportClock;
  final AppClock clock;
  final FtsUpdater ftsUpdater;
  final ChangeLogRepository changeLogRepository;

  Future<PagedResult<TodoListItem>> listTodos({
    int page = 0,
    int pageSize = defaultPageSize,
  }) async {
    final List<Map<String, Object?>> rows = await database.db.rawQuery(
      '''
      SELECT t.id, t.title, t.priority, t.status,
             COUNT(et.tag_id) AS tag_count
      FROM todos t
      LEFT JOIN entity_tags et ON et.entity_type='todo' AND et.entity_id=t.id
      WHERE t.deleted = 0
      GROUP BY t.id
      ORDER BY t.priority DESC, t.created_at DESC
      LIMIT ? OFFSET ?
      ''',
      <Object?>[pageSize, page * pageSize],
    );

    final List<TodoListItem> items = rows
        .map(
          (Map<String, Object?> row) => TodoListItem(
            id: row['id']! as String,
            title: row['title']! as String,
            priority: row['priority']! as int,
            status: row['status']! as int,
            tagCount: (row['tag_count'] as num).toInt(),
          ),
        )
        .toList(growable: false);

    // M1 simplification: hasMore based on current page size.
    // If the last page size equals pageSize, one extra empty load may happen.
    return PagedResult<TodoListItem>(
      items: items,
      hasMore: items.length == pageSize,
    );
  }

  Future<TodoDetail?> getTodoDetail(String todoId) async {
    final List<Map<String, Object?>> rows = await database.db.rawQuery(
      '''
      SELECT id, title, priority, status, remind_at
      FROM todos
      WHERE id = ? AND deleted = 0
      LIMIT 1
      ''',
      <Object?>[todoId],
    );
    if (rows.isEmpty) {
      return null;
    }

    final List<String> tags = await _loadTagsForEntity('todo', todoId);
    final Map<String, Object?> row = rows.first;
    return TodoDetail(
      id: row['id']! as String,
      title: row['title']! as String,
      priority: (row['priority'] as num).toInt(),
      status: (row['status'] as num).toInt(),
      remindAt: (row['remind_at'] as num?)?.toInt(),
      tags: tags,
    );
  }

  Future<void> updateTodoDetail({
    required String todoId,
    required String title,
    required int priority,
    required int status,
    required int? remindAt,
    required List<String> tags,
  }) async {
    await database.db.transaction((txn) async {
      final int now = clock.nowMs();
      final int lamport = await lamportClock.next(txn);
      final String deviceId = await identityService.getOrCreateDeviceId(txn);

      await txn.update(
        'todos',
        <String, Object?>{
          'title': title,
          'priority': priority,
          'status': status,
          'remind_at': remindAt,
          'updated_at': now,
          'lamport': lamport,
        },
        where: 'id = ?',
        whereArgs: <Object?>[todoId],
      );

      await _replaceEntityTags(
        txn: txn,
        entityType: 'todo',
        entityId: todoId,
        tags: tags,
        lamport: lamport,
        deviceId: deviceId,
        now: now,
      );
      await ftsUpdater.upsertTodo(txn, todoId);
      await changeLogRepository.append(
        executor: txn,
        entityType: 'todo',
        entityId: todoId,
        operation: SyncOperation.upsert,
        lamport: lamport,
        deviceId: deviceId,
        createdAt: now,
      );
    });
  }

  Future<void> deleteTodo(String todoId) async {
    await database.db.transaction((txn) async {
      final int now = clock.nowMs();
      final int lamport = await lamportClock.next(txn);
      final String deviceId = await identityService.getOrCreateDeviceId(txn);
      await txn.update(
        'todos',
        <String, Object?>{'deleted': 1, 'updated_at': now, 'lamport': lamport},
        where: 'id = ?',
        whereArgs: <Object?>[todoId],
      );
      await ftsUpdater.upsertTodo(txn, todoId);
      await changeLogRepository.append(
        executor: txn,
        entityType: 'todo',
        entityId: todoId,
        operation: SyncOperation.delete,
        lamport: lamport,
        deviceId: deviceId,
        createdAt: now,
      );
    });
  }

  Future<PagedResult<NoteListItem>> listNotes({
    int page = 0,
    int pageSize = defaultPageSize,
  }) async {
    final List<Map<String, Object?>> rows = await database.db.rawQuery(
      '''
      SELECT id, title, latest_version
      FROM notes
      WHERE deleted = 0
      ORDER BY updated_at DESC
      LIMIT ? OFFSET ?
      ''',
      <Object?>[pageSize, page * pageSize],
    );

    final List<NoteListItem> items = rows
        .map(
          (Map<String, Object?> row) => NoteListItem(
            id: row['id']! as String,
            title: row['title']! as String,
            latestVersion: (row['latest_version'] as num).toInt(),
          ),
        )
        .toList(growable: false);

    return PagedResult<NoteListItem>(
      items: items,
      hasMore: items.length == pageSize,
    );
  }

  Future<NoteDetail?> getNoteDetail(String noteId) async {
    final List<Map<String, Object?>> rows = await database.db.rawQuery(
      '''
      SELECT n.id, n.title, n.raw_text, n.latest_version, nv.organized_md
      FROM notes n
      LEFT JOIN note_versions nv ON nv.note_id = n.id AND nv.version = n.latest_version
      WHERE n.id = ? AND n.deleted = 0
      LIMIT 1
      ''',
      <Object?>[noteId],
    );
    if (rows.isEmpty) {
      return null;
    }
    final Map<String, Object?> row = rows.first;
    return NoteDetail(
      id: row['id']! as String,
      title: row['title']! as String,
      rawText: row['raw_text']! as String,
      latestVersion: (row['latest_version'] as num).toInt(),
      organizedMd: (row['organized_md'] as String?) ?? '',
    );
  }

  Future<List<NoteVersionItem>> listNoteVersions(String noteId) async {
    final List<Map<String, Object?>> rows = await database.db.rawQuery(
      '''
      SELECT version, created_at
      FROM note_versions
      WHERE note_id = ?
      ORDER BY version DESC
      ''',
      <Object?>[noteId],
    );
    return rows
        .map(
          (Map<String, Object?> row) => NoteVersionItem(
            version: (row['version'] as num).toInt(),
            createdAt: (row['created_at'] as num).toInt(),
          ),
        )
        .toList(growable: false);
  }

  Future<String?> getNoteVersionContent({
    required String noteId,
    required int version,
  }) async {
    final List<Map<String, Object?>> rows = await database.db.query(
      'note_versions',
      columns: <String>['organized_md'],
      where: 'note_id = ? AND version = ?',
      whereArgs: <Object?>[noteId, version],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return (rows.first['organized_md'] as String?) ?? '';
  }

  Future<void> appendNoteVersion({
    required String noteId,
    required String organizedMd,
    int keepLatest = 5,
  }) async {
    await database.db.transaction((txn) async {
      final List<Map<String, Object?>> rows = await txn.query(
        'notes',
        columns: <String>['latest_version'],
        where: 'id = ?',
        whereArgs: <Object?>[noteId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw Exception('笔记不存在');
      }
      final int currentVersion = (rows.first['latest_version'] as num).toInt();
      final int nextVersion = currentVersion + 1;
      final int now = clock.nowMs();
      final int lamport = await lamportClock.next(txn);

      await txn.insert('note_versions', <String, Object?>{
        'note_id': noteId,
        'version': nextVersion,
        'organized_md': organizedMd,
        'created_at': now,
      });

      await txn.update(
        'notes',
        <String, Object?>{
          'latest_version': nextVersion,
          'updated_at': now,
          'lamport': lamport,
        },
        where: 'id = ?',
        whereArgs: <Object?>[noteId],
      );

      await _pruneNoteVersionsTxn(txn, noteId: noteId, keepLatest: keepLatest);

      await ftsUpdater.upsertNote(txn, noteId);
      final String deviceId = await identityService.getOrCreateDeviceId(txn);
      await changeLogRepository.append(
        executor: txn,
        entityType: 'note',
        entityId: noteId,
        operation: SyncOperation.upsert,
        lamport: lamport,
        deviceId: deviceId,
        createdAt: now,
      );
    });
  }

  Future<void> pruneNoteVersions({
    required String noteId,
    required int keepLatest,
  }) async {
    await database.db.transaction((txn) async {
      await _pruneNoteVersionsTxn(txn, noteId: noteId, keepLatest: keepLatest);
      final int now = clock.nowMs();
      final int lamport = await lamportClock.next(txn);
      final String deviceId = await identityService.getOrCreateDeviceId(txn);
      await txn.update(
        'notes',
        <String, Object?>{'updated_at': now, 'lamport': lamport},
        where: 'id = ?',
        whereArgs: <Object?>[noteId],
      );
      await changeLogRepository.append(
        executor: txn,
        entityType: 'note',
        entityId: noteId,
        operation: SyncOperation.upsert,
        lamport: lamport,
        deviceId: deviceId,
        createdAt: now,
      );
    });
  }

  Future<PagedResult<BookmarkListItem>> listBookmarks({
    int page = 0,
    int pageSize = defaultPageSize,
  }) async {
    final List<Map<String, Object?>> rows = await database.db.rawQuery(
      '''
      SELECT id, title, url
      FROM bookmarks
      WHERE deleted = 0
      ORDER BY updated_at DESC
      LIMIT ? OFFSET ?
      ''',
      <Object?>[pageSize, page * pageSize],
    );

    final List<BookmarkListItem> items = rows
        .map(
          (Map<String, Object?> row) => BookmarkListItem(
            id: row['id']! as String,
            title: (row['title'] as String?)?.trim().isNotEmpty == true
                ? row['title']! as String
                : row['url']! as String,
            url: row['url']! as String,
          ),
        )
        .toList(growable: false);

    return PagedResult<BookmarkListItem>(
      items: items,
      hasMore: items.length == pageSize,
    );
  }

  Future<BookmarkDetail?> getBookmarkDetail(String bookmarkId) async {
    final List<Map<String, Object?>> rows = await database.db.rawQuery(
      '''
      SELECT id, title, url, last_fetched_at
      FROM bookmarks
      WHERE id = ? AND deleted = 0
      LIMIT 1
      ''',
      <Object?>[bookmarkId],
    );
    if (rows.isEmpty) {
      return null;
    }
    final List<String> tags = await _loadTagsForEntity('bookmark', bookmarkId);
    final Map<String, Object?> row = rows.first;
    return BookmarkDetail(
      id: row['id']! as String,
      title: ((row['title'] as String?)?.trim().isNotEmpty ?? false)
          ? row['title']! as String
          : row['url']! as String,
      url: row['url']! as String,
      lastFetchedAt: (row['last_fetched_at'] as num?)?.toInt(),
      tags: tags,
    );
  }

  Future<void> updateBookmarkTags({
    required String bookmarkId,
    required List<String> tags,
  }) async {
    await database.db.transaction((txn) async {
      final int now = clock.nowMs();
      final int lamport = await lamportClock.next(txn);
      final String deviceId = await identityService.getOrCreateDeviceId(txn);
      await _replaceEntityTags(
        txn: txn,
        entityType: 'bookmark',
        entityId: bookmarkId,
        tags: tags,
        lamport: lamport,
        deviceId: deviceId,
        now: now,
      );
      await txn.update(
        'bookmarks',
        <String, Object?>{'updated_at': now, 'lamport': lamport},
        where: 'id = ?',
        whereArgs: <Object?>[bookmarkId],
      );
      await ftsUpdater.upsertBookmark(txn, bookmarkId);
      await changeLogRepository.append(
        executor: txn,
        entityType: 'bookmark',
        entityId: bookmarkId,
        operation: SyncOperation.upsert,
        lamport: lamport,
        deviceId: deviceId,
        createdAt: now,
      );
    });
  }

  Future<void> deleteBookmark(String bookmarkId) async {
    await database.db.transaction((txn) async {
      final int now = clock.nowMs();
      final int lamport = await lamportClock.next(txn);
      final String deviceId = await identityService.getOrCreateDeviceId(txn);
      await txn.update(
        'bookmarks',
        <String, Object?>{'deleted': 1, 'updated_at': now, 'lamport': lamport},
        where: 'id = ?',
        whereArgs: <Object?>[bookmarkId],
      );
      await ftsUpdater.upsertBookmark(txn, bookmarkId);
      await changeLogRepository.append(
        executor: txn,
        entityType: 'bookmark',
        entityId: bookmarkId,
        operation: SyncOperation.delete,
        lamport: lamport,
        deviceId: deviceId,
        createdAt: now,
      );
    });
  }

  Future<List<String>> listAllBookmarkIds() async {
    final List<Map<String, Object?>> rows = await database.db.rawQuery('''
      SELECT id
      FROM bookmarks
      WHERE deleted = 0
      ORDER BY updated_at DESC
      ''');
    return rows
        .map((Map<String, Object?> row) => row['id']! as String)
        .toList(growable: false);
  }

  Future<void> setTodoStatus({
    required String todoId,
    required bool done,
  }) async {
    await database.db.transaction((txn) async {
      final int now = clock.nowMs();
      final int lamport = await lamportClock.next(txn);
      await txn.update(
        'todos',
        <String, Object?>{
          'status': done ? TodoStatusCode.done : TodoStatusCode.open,
          'updated_at': now,
          'lamport': lamport,
        },
        where: 'id = ?',
        whereArgs: <Object?>[todoId],
      );
      await ftsUpdater.upsertTodo(txn, todoId);
      final String deviceId = await identityService.getOrCreateDeviceId(txn);
      await changeLogRepository.append(
        executor: txn,
        entityType: 'todo',
        entityId: todoId,
        operation: SyncOperation.upsert,
        lamport: lamport,
        deviceId: deviceId,
        createdAt: now,
      );
    });
  }

  Future<void> refreshBookmarkTitle({
    required String bookmarkId,
    required BookmarkTitleFetcher fetcher,
  }) async {
    await database.db.transaction((txn) async {
      final List<Map<String, Object?>> rows = await txn.query(
        'bookmarks',
        columns: <String>['url', 'device_id'],
        where: 'id = ?',
        whereArgs: <Object?>[bookmarkId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw Exception('收藏不存在');
      }

      final String url = rows.first['url']! as String;
      final String title = await fetcher.fetchTitle(url);
      final int now = clock.nowMs();
      final int lamport = await lamportClock.next(txn);

      await txn.update(
        'bookmarks',
        <String, Object?>{
          'title': title,
          'last_fetched_at': now,
          'updated_at': now,
          'lamport': lamport,
        },
        where: 'id = ?',
        whereArgs: <Object?>[bookmarkId],
      );

      await ftsUpdater.upsertBookmark(txn, bookmarkId);
      await changeLogRepository.append(
        executor: txn,
        entityType: 'bookmark',
        entityId: bookmarkId,
        operation: SyncOperation.upsert,
        lamport: lamport,
        deviceId: rows.first['device_id']! as String,
        createdAt: now,
      );
    });
  }

  Future<void> seedDebugData({
    int todoCount = 700,
    int noteCount = 200,
    int bookmarkCount = 100,
  }) async {
    await database.db.transaction((txn) async {
      final String deviceId = await identityService.getOrCreateDeviceId(txn);
      final int now = clock.nowMs();
      final int total = todoCount + noteCount + bookmarkCount;
      final int reservedBase = await lamportClock.reserve(txn, total);
      int lamport = reservedBase;

      final Batch batch = txn.batch();

      for (int i = 0; i < todoCount; i++) {
        lamport += 1;
        final int createdAt = now - (i * 1000);
        batch.insert('todos', <String, Object?>{
          'id': _uuid.v4(),
          'title': 'Todo #$i',
          'priority': (i % 3 == 0)
              ? TodoPriorityCode.high
              : (i % 3 == 1)
              ? TodoPriorityCode.medium
              : TodoPriorityCode.low,
          'status': i % 5 == 0 ? TodoStatusCode.done : TodoStatusCode.open,
          'remind_at': null,
          'created_at': createdAt,
          'updated_at': createdAt,
          'deleted': 0,
          'lamport': lamport,
          'device_id': deviceId,
        });
      }

      for (int i = 0; i < noteCount; i++) {
        lamport += 1;
        final String noteId = _uuid.v4();
        final int createdAt = now - (todoCount + i) * 1000;
        batch.insert('notes', <String, Object?>{
          'id': noteId,
          'title': 'Note #$i',
          'raw_text': 'Raw content #$i',
          'latest_version': 1,
          'created_at': createdAt,
          'updated_at': createdAt,
          'deleted': 0,
          'lamport': lamport,
          'device_id': deviceId,
        });
        batch.insert('note_versions', <String, Object?>{
          'note_id': noteId,
          'version': 1,
          'organized_md': '# Note #$i\n\nGenerated for debug seeding.',
          'created_at': createdAt,
        });
      }

      for (int i = 0; i < bookmarkCount; i++) {
        lamport += 1;
        final int createdAt = now - (todoCount + noteCount + i) * 1000;
        batch.insert('bookmarks', <String, Object?>{
          'id': _uuid.v4(),
          'url': 'https://example.com/item-$i',
          'title': i % 4 == 0 ? '' : 'Bookmark #$i',
          'last_fetched_at': createdAt,
          'created_at': createdAt,
          'updated_at': createdAt,
          'deleted': 0,
          'lamport': lamport,
          'device_id': deviceId,
        });
      }

      await batch.commit(noResult: true);
      await ftsUpdater.rebuildAll(txn);
    });
  }

  Future<void> clearLibraryData() async {
    await database.db.transaction((txn) async {
      await txn.delete('entity_tags');
      await txn.delete('tags');
      await txn.delete('note_versions');
      await txn.delete('todos');
      await txn.delete('notes');
      await txn.delete('bookmarks');
      await txn.delete('search_fts');
    });
  }

  Future<void> _pruneNoteVersionsTxn(
    Transaction txn, {
    required String noteId,
    required int keepLatest,
  }) async {
    final int keep = keepLatest.clamp(1, 100);
    await txn.delete(
      'note_versions',
      where:
          'note_id = ? AND version NOT IN (SELECT version FROM note_versions WHERE note_id = ? ORDER BY version DESC LIMIT ?)',
      whereArgs: <Object?>[noteId, noteId, keep],
    );

    final List<Map<String, Object?>> rows = await txn.rawQuery(
      '''
      SELECT MAX(version) AS latest
      FROM note_versions
      WHERE note_id = ?
      ''',
      <Object?>[noteId],
    );
    final int? latest = (rows.first['latest'] as num?)?.toInt();
    if (latest != null) {
      await txn.update(
        'notes',
        <String, Object?>{'latest_version': latest},
        where: 'id = ?',
        whereArgs: <Object?>[noteId],
      );
    }
  }

  Future<void> _replaceEntityTags({
    required Transaction txn,
    required String entityType,
    required String entityId,
    required List<String> tags,
    required int lamport,
    required String deviceId,
    required int now,
  }) async {
    await txn.delete(
      'entity_tags',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: <Object?>[entityType, entityId],
    );

    final List<String> normalized = _normalizeTags(tags);
    for (final String tagName in normalized) {
      final List<Map<String, Object?>> existing = await txn.query(
        'tags',
        columns: <String>['id'],
        where: 'name = ?',
        whereArgs: <Object?>[tagName],
        limit: 1,
      );

      String tagId;
      if (existing.isEmpty) {
        tagId = _uuid.v4();
        await txn.insert('tags', <String, Object?>{
          'id': tagId,
          'name': tagName,
          'created_at': now,
        });
        await changeLogRepository.append(
          executor: txn,
          entityType: 'tag',
          entityId: tagId,
          operation: SyncOperation.upsert,
          lamport: lamport,
          deviceId: deviceId,
          createdAt: now,
        );
      } else {
        tagId = existing.first['id']! as String;
      }

      await txn.insert('entity_tags', <String, Object?>{
        'entity_type': entityType,
        'entity_id': entityId,
        'tag_id': tagId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<List<String>> _loadTagsForEntity(
    String entityType,
    String entityId,
  ) async {
    final List<Map<String, Object?>> rows = await database.db.rawQuery(
      '''
      SELECT tags.name
      FROM entity_tags et
      JOIN tags ON tags.id = et.tag_id
      WHERE et.entity_type = ? AND et.entity_id = ?
      ORDER BY tags.name COLLATE NOCASE ASC
      ''',
      <Object?>[entityType, entityId],
    );
    return rows
        .map((Map<String, Object?> row) => row['name']! as String)
        .toList(growable: false);
  }

  List<String> _normalizeTags(List<String> tags) {
    final Set<String> values = <String>{};
    for (final String raw in tags) {
      final String normalized = raw.trim();
      if (normalized.isNotEmpty) {
        values.add(normalized);
      }
    }
    return values.toList(growable: false);
  }
}
