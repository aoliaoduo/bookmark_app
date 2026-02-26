import '../clock/app_clock.dart';
import '../db/app_database.dart';
import '../search/fts_updater.dart';

class MaintenanceResult {
  const MaintenanceResult({required this.action, required this.summary});

  final String action;
  final String summary;
}

class MaintenanceService {
  MaintenanceService({
    required this.database,
    required this.clock,
    required this.ftsUpdater,
  });

  final AppDatabase database;
  final AppClock clock;
  final FtsUpdater ftsUpdater;

  Future<MaintenanceResult> purgeSoftDeleted({
    required int olderThanDays,
  }) async {
    final int now = clock.nowMs();
    final int threshold = now - olderThanDays * 24 * 60 * 60 * 1000;
    final result = await database.db.transaction((txn) async {
      final int deletedTodos = await txn.delete(
        'todos',
        where: 'deleted = 1 AND updated_at < ?',
        whereArgs: <Object?>[threshold],
      );
      final int deletedNotes = await txn.delete(
        'notes',
        where: 'deleted = 1 AND updated_at < ?',
        whereArgs: <Object?>[threshold],
      );
      final int deletedBookmarks = await txn.delete(
        'bookmarks',
        where: 'deleted = 1 AND updated_at < ?',
        whereArgs: <Object?>[threshold],
      );
      final int deletedNoteVersions = await txn.rawDelete(
        'DELETE FROM note_versions WHERE note_id NOT IN (SELECT id FROM notes)',
      );
      final int deletedEntityTags = await txn.rawDelete('''
        DELETE FROM entity_tags
        WHERE (entity_type='todo' AND entity_id NOT IN (SELECT id FROM todos))
           OR (entity_type='note' AND entity_id NOT IN (SELECT id FROM notes))
           OR (entity_type='bookmark' AND entity_id NOT IN (SELECT id FROM bookmarks))
      ''');
      final int deletedFts = await txn.rawDelete('''
        DELETE FROM search_fts
        WHERE (entity_type='todo' AND entity_id NOT IN (SELECT id FROM todos WHERE deleted=0))
           OR (entity_type='note' AND entity_id NOT IN (SELECT id FROM notes WHERE deleted=0))
           OR (entity_type='bookmark' AND entity_id NOT IN (SELECT id FROM bookmarks WHERE deleted=0))
      ''');
      return (
        deletedTodos,
        deletedNotes,
        deletedBookmarks,
        deletedNoteVersions,
        deletedEntityTags,
        deletedFts,
      );
    });

    return MaintenanceResult(
      action: 'purge_soft_deleted',
      summary:
          'todo=${result.$1}, note=${result.$2}, bookmark=${result.$3}, '
          'note_versions=${result.$4}, entity_tags=${result.$5}, fts=${result.$6}',
    );
  }

  Future<MaintenanceResult> purgeOrphanTags() async {
    final int deleted = await database.db.rawDelete(
      'DELETE FROM tags WHERE id NOT IN (SELECT DISTINCT tag_id FROM entity_tags)',
    );
    return MaintenanceResult(
      action: 'purge_orphan_tags',
      summary: 'deleted_tags=$deleted',
    );
  }

  Future<MaintenanceResult> rebuildFts() async {
    await database.db.transaction((txn) async {
      await ftsUpdater.rebuildAll(txn);
    });
    final List<Map<String, Object?>> countRows = await database.db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM search_fts',
    );
    final int count = (countRows.first['cnt'] as num?)?.toInt() ?? 0;
    return MaintenanceResult(action: 'rebuild_fts', summary: 'fts_rows=$count');
  }

  Future<MaintenanceResult> optimizeVacuum() async {
    await database.db.execute('PRAGMA optimize');
    await database.db.execute('VACUUM');
    return const MaintenanceResult(
      action: 'optimize_vacuum',
      summary: 'PRAGMA optimize + VACUUM done',
    );
  }

  Future<MaintenanceResult> purgeNoteHistoryKeepLatest() async {
    final int deleted = await database.db.rawDelete('''
      DELETE FROM note_versions
      WHERE note_id IN (SELECT id FROM notes)
        AND version < (
          SELECT latest_version
          FROM notes
          WHERE notes.id = note_versions.note_id
        )
    ''');
    final int deletedOrphans = await database.db.rawDelete(
      'DELETE FROM note_versions WHERE note_id NOT IN (SELECT id FROM notes)',
    );
    return MaintenanceResult(
      action: 'purge_note_versions_keep_latest',
      summary: 'deleted_versions=$deleted, deleted_orphans=$deletedOrphans',
    );
  }
}
