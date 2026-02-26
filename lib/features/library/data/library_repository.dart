import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/bookmark/bookmark_title_fetcher.dart';
import '../../../core/clock/app_clock.dart';
import '../../../core/clock/lamport_clock.dart';
import '../../../core/db/app_database.dart';
import '../../../core/identity/device_identity_service.dart';
import '../../../core/search/fts_updater.dart';

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

class LibraryRepository {
  LibraryRepository({
    required this.database,
    required this.identityService,
    required this.lamportClock,
    required this.clock,
    required this.ftsUpdater,
  });

  static const int defaultPageSize = 50;
  static const Uuid _uuid = Uuid();

  final AppDatabase database;
  final DeviceIdentityService identityService;
  final LamportClock lamportClock;
  final AppClock clock;
  final FtsUpdater ftsUpdater;

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
            tagCount: row['tag_count']! as int,
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

  Future<PagedResult<NoteListItem>> listNotes({
    int page = 0,
    int pageSize = defaultPageSize,
  }) async {
    // Notes sorted by updated_at for most-recent-first reading.
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
            latestVersion: row['latest_version']! as int,
          ),
        )
        .toList(growable: false);

    return PagedResult<NoteListItem>(
      items: items,
      hasMore: items.length == pageSize,
    );
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

  Future<void> setTodoStatus({
    required String todoId,
    required bool done,
  }) async {
    await database.db.transaction((txn) async {
      final int now = clock.nowMs();
      final int lamport = await lamportClock.next(txn);
      await txn.update(
        'todos',
        {
          'status': done ? TodoStatusCode.done : TodoStatusCode.open,
          'updated_at': now,
          'lamport': lamport,
        },
        where: 'id = ?',
        whereArgs: <Object?>[todoId],
      );
      await ftsUpdater.upsertTodo(txn, todoId);
    });
  }

  Future<void> refreshBookmarkTitle({
    required String bookmarkId,
    required BookmarkTitleFetcher fetcher,
  }) async {
    await database.db.transaction((txn) async {
      final List<Map<String, Object?>> rows = await txn.query(
        'bookmarks',
        columns: ['url'],
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
        batch.insert('todos', {
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
        batch.insert('notes', {
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
        batch.insert('note_versions', {
          'note_id': noteId,
          'version': 1,
          'organized_md': '# Note #$i\n\nGenerated for debug seeding.',
          'created_at': createdAt,
        });
      }

      for (int i = 0; i < bookmarkCount; i++) {
        lamport += 1;
        final int createdAt = now - (todoCount + noteCount + i) * 1000;
        batch.insert('bookmarks', {
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
}
