import 'package:sqflite/sqflite.dart';

class FtsUpdater {
  Future<void> upsertTodo(DatabaseExecutor db, String todoId) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT t.id, t.title,
             COALESCE(GROUP_CONCAT(tags.name, ' '), '') AS tags_text
      FROM todos t
      LEFT JOIN entity_tags et ON et.entity_type = 'todo' AND et.entity_id = t.id
      LEFT JOIN tags ON tags.id = et.tag_id
      WHERE t.id = ? AND t.deleted = 0
      GROUP BY t.id
      LIMIT 1
      ''',
      <Object?>[todoId],
    );

    await _replaceEntity(
      db,
      entityType: 'todo',
      entityId: todoId,
      row: rows.isEmpty ? null : rows.first,
      bodyField: '',
    );
  }

  Future<void> upsertNote(DatabaseExecutor db, String noteId) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT n.id, n.title, n.raw_text,
             COALESCE(nv.organized_md, '') AS organized_md,
             COALESCE(GROUP_CONCAT(tags.name, ' '), '') AS tags_text
      FROM notes n
      LEFT JOIN note_versions nv ON nv.note_id = n.id AND nv.version = n.latest_version
      LEFT JOIN entity_tags et ON et.entity_type = 'note' AND et.entity_id = n.id
      LEFT JOIN tags ON tags.id = et.tag_id
      WHERE n.id = ? AND n.deleted = 0
      GROUP BY n.id
      LIMIT 1
      ''',
      <Object?>[noteId],
    );

    if (rows.isEmpty) {
      await _replaceEntity(
        db,
        entityType: 'note',
        entityId: noteId,
        row: null,
        bodyField: '',
      );
      return;
    }

    final row = rows.first;
    await _replaceEntity(
      db,
      entityType: 'note',
      entityId: noteId,
      row: <String, Object?>{
        'title': row['title'] ?? '',
        'body': '${row['raw_text'] ?? ''}\n${row['organized_md'] ?? ''}',
        'tags_text': row['tags_text'] ?? '',
      },
      bodyField: 'body',
    );
  }

  Future<void> upsertBookmark(DatabaseExecutor db, String bookmarkId) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT b.id, b.title, b.url,
             COALESCE(GROUP_CONCAT(tags.name, ' '), '') AS tags_text
      FROM bookmarks b
      LEFT JOIN entity_tags et ON et.entity_type = 'bookmark' AND et.entity_id = b.id
      LEFT JOIN tags ON tags.id = et.tag_id
      WHERE b.id = ? AND b.deleted = 0
      GROUP BY b.id
      LIMIT 1
      ''',
      <Object?>[bookmarkId],
    );

    if (rows.isEmpty) {
      await _replaceEntity(
        db,
        entityType: 'bookmark',
        entityId: bookmarkId,
        row: null,
        bodyField: '',
      );
      return;
    }

    final row = rows.first;
    await _replaceEntity(
      db,
      entityType: 'bookmark',
      entityId: bookmarkId,
      row: <String, Object?>{
        'title': ((row['title'] as String?)?.isNotEmpty ?? false)
            ? row['title'] as String
            : row['url'] as String,
        'body': row['url'] as String,
        'tags_text': row['tags_text'] ?? '',
      },
      bodyField: 'body',
    );
  }

  Future<void> rebuildAll(DatabaseExecutor db) async {
    await db.delete('search_fts');

    final todoRows = await db.rawQuery(
      'SELECT id FROM todos WHERE deleted = 0;',
    );
    for (final row in todoRows) {
      await upsertTodo(db, row['id']! as String);
    }

    final noteRows = await db.rawQuery(
      'SELECT id FROM notes WHERE deleted = 0;',
    );
    for (final row in noteRows) {
      await upsertNote(db, row['id']! as String);
    }

    final bookmarkRows = await db.rawQuery(
      'SELECT id FROM bookmarks WHERE deleted = 0;',
    );
    for (final row in bookmarkRows) {
      await upsertBookmark(db, row['id']! as String);
    }
  }

  Future<void> _replaceEntity(
    DatabaseExecutor db, {
    required String entityType,
    required String entityId,
    required Map<String, Object?>? row,
    required String bodyField,
  }) async {
    await db.delete(
      'search_fts',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: <Object?>[entityType, entityId],
    );

    if (row == null) {
      return;
    }

    await db.insert('search_fts', {
      'entity_type': entityType,
      'entity_id': entityId,
      'title': row['title'] ?? '',
      'body': bodyField.isEmpty ? '' : (row[bodyField] ?? ''),
      'tags': row['tags_text'] ?? '',
    });
  }
}
