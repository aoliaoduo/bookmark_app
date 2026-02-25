import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/domain/bookmark.dart';
import '../../core/metadata/metadata_fetch_service.dart';
import '../../core/metadata/title_fetch_note.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_types.dart';

class DedupResult {
  const DedupResult({required this.exactRemoved, required this.similarRemoved});

  final int exactRemoved;
  final int similarRemoved;

  int get totalRemoved => exactRemoved + similarRemoved;
}

class BookmarkRepository implements LocalStore {
  BookmarkRepository({
    required Database db,
    required MetadataFetchService metadataService,
    required String deviceId,
  }) : _db = db,
       _metadataService = metadataService,
       _deviceId = deviceId;

  final Database _db;
  final MetadataFetchService _metadataService;
  final String _deviceId;
  final Uuid _uuid = const Uuid();
  static const Duration _tombstoneRetention = Duration(days: 365);

  void dispose() {
    _metadataService.close();
  }

  Future<List<Bookmark>> listBookmarks({bool includeDeleted = false}) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'bookmarks',
      where: includeDeleted ? null : 'deleted_at IS NULL',
      orderBy: 'updated_at DESC',
    );
    return rows.map(_bookmarkFromRow).toList();
  }

  Future<List<Bookmark>> listTrashBookmarks() async {
    final List<Map<String, Object?>> rows = await _db.query(
      'bookmarks',
      where: 'deleted_at IS NOT NULL',
      orderBy: 'deleted_at DESC',
    );
    return rows.map(_bookmarkFromRow).toList();
  }

  Future<Bookmark?> findById(String id) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'bookmarks',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _bookmarkFromRow(rows.first);
  }

  @override
  Future<Bookmark?> findBookmarkById(String bookmarkId) {
    return findById(bookmarkId);
  }

  @override
  Future<DateTime?> findTombstoneAt(String bookmarkId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'sync_tombstones',
      columns: <String>['deleted_at'],
      where: 'bookmark_id = ?',
      whereArgs: <Object?>[bookmarkId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return DateTime.parse(rows.first['deleted_at']! as String).toUtc();
  }

  @override
  Future<void> saveTombstone(String bookmarkId, DateTime deletedAt) async {
    await _upsertTombstoneLocal(bookmarkId, deletedAt);
  }

  @override
  Future<void> clearTombstone(String bookmarkId) async {
    await _deleteTombstoneLocal(bookmarkId);
  }

  Future<Bookmark> addUrl(String rawInput) async {
    final String normalized = _normalizeUrl(rawInput);
    final String now = DateTime.now().toUtc().toIso8601String();

    final List<Map<String, Object?>> exists = await _db.query(
      'bookmarks',
      where: 'normalized_url = ? AND deleted_at IS NULL',
      whereArgs: <Object?>[normalized],
      limit: 1,
    );
    if (exists.isNotEmpty) {
      return _bookmarkFromRow(exists.first);
    }

    final Bookmark bookmark = Bookmark(
      id: _uuid.v4(),
      url: normalized,
      normalizedUrl: normalized,
      title: null,
      note: null,
      tags: const <String>[],
      createdAt: DateTime.parse(now),
      updatedAt: DateTime.parse(now),
      deletedAt: null,
      titleUpdatedAt: null,
    );

    await _writeBookmarkAndOutbox(
      bookmark: bookmark,
      opType: SyncOpType.upsert,
    );

    return bookmark;
  }

  Future<Bookmark?> refreshTitle(String bookmarkId) async {
    final Bookmark? bookmark = await findById(bookmarkId);
    if (bookmark == null || bookmark.isDeleted) return null;
    final DateTime now = DateTime.now().toUtc();
    try {
      final UrlMetadata metadata = await _metadataService.fetchTitle(
        bookmark.url,
      );
      final Bookmark updated = bookmark.copyWith(
        title: metadata.title ?? bookmark.title,
        note: null,
        titleUpdatedAt: now,
        updatedAt: now,
      );

      await _writeBookmarkAndOutbox(
        bookmark: updated,
        opType: SyncOpType.upsert,
      );
      return updated;
    } on MetadataFetchException catch (e) {
      final Bookmark failed = bookmark.copyWith(
        note: buildTitleFetchFailureNote(e.message),
        titleUpdatedAt: now,
        updatedAt: now,
      );
      await _writeBookmarkAndOutbox(
        bookmark: failed,
        opType: SyncOpType.upsert,
      );
      return failed;
    } catch (_) {
      final Bookmark failed = bookmark.copyWith(
        note: buildTitleFetchFailureNote('无法连接该链接，请检查是否可访问'),
        titleUpdatedAt: now,
        updatedAt: now,
      );
      await _writeBookmarkAndOutbox(
        bookmark: failed,
        opType: SyncOpType.upsert,
      );
      return failed;
    }
  }

  Future<Bookmark?> clearNote(String bookmarkId) async {
    final Bookmark? bookmark = await findById(bookmarkId);
    if (bookmark == null || bookmark.isDeleted) return null;
    final DateTime now = DateTime.now().toUtc();
    final Bookmark updated = bookmark.copyWith(note: null, updatedAt: now);
    await _writeBookmarkAndOutbox(bookmark: updated, opType: SyncOpType.upsert);
    return updated;
  }

  Future<int> refreshTitlesOlderThan(Duration ttl) async {
    final DateTime threshold = DateTime.now().toUtc().subtract(ttl);
    final List<Map<String, Object?>> rows = await _db.query(
      'bookmarks',
      where:
          'deleted_at IS NULL AND (title_updated_at IS NULL OR title_updated_at < ?)',
      whereArgs: <Object?>[threshold.toIso8601String()],
      orderBy: 'updated_at ASC',
      limit: 500,
    );

    final List<Bookmark> targets = rows.map(_bookmarkFromRow).toList();
    return _refreshTitlesInParallel(targets, maxConcurrent: 8);
  }

  Future<int> refreshTitlesOlderThanWithProgress(
    Duration ttl, {
    int maxConcurrent = 8,
    void Function(int processed, int total, int updated)? onProgress,
  }) async {
    final DateTime threshold = DateTime.now().toUtc().subtract(ttl);
    final List<Map<String, Object?>> rows = await _db.query(
      'bookmarks',
      where:
          'deleted_at IS NULL AND (title_updated_at IS NULL OR title_updated_at < ?)',
      whereArgs: <Object?>[threshold.toIso8601String()],
      orderBy: 'updated_at ASC',
      limit: 500,
    );
    final List<Bookmark> targets = rows.map(_bookmarkFromRow).toList();
    return _refreshTitlesInParallel(
      targets,
      maxConcurrent: maxConcurrent,
      onProgress: onProgress,
    );
  }

  Future<int> refreshAllTitles({int maxConcurrent = 8}) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'bookmarks',
      where: 'deleted_at IS NULL',
      orderBy: 'updated_at ASC',
    );
    final List<Bookmark> targets = rows.map(_bookmarkFromRow).toList();
    return _refreshTitlesInParallel(targets, maxConcurrent: maxConcurrent);
  }

  Future<int> refreshAllTitlesWithProgress({
    int maxConcurrent = 8,
    void Function(int processed, int total, int updated)? onProgress,
  }) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'bookmarks',
      where: 'deleted_at IS NULL',
      orderBy: 'updated_at ASC',
    );
    final List<Bookmark> targets = rows.map(_bookmarkFromRow).toList();
    return _refreshTitlesInParallel(
      targets,
      maxConcurrent: maxConcurrent,
      onProgress: onProgress,
    );
  }

  Future<int> refreshTitlesByIdsWithProgress(
    List<String> bookmarkIds, {
    int maxConcurrent = 8,
    void Function(int processed, int total, int updated)? onProgress,
  }) async {
    final List<String> ids = _distinctIds(bookmarkIds);
    if (ids.isEmpty) {
      onProgress?.call(0, 0, 0);
      return 0;
    }
    final List<Bookmark> targets = await _loadBookmarksByIds(
      ids,
      includeDeleted: false,
    );
    return _refreshTitlesInParallel(
      targets,
      maxConcurrent: maxConcurrent,
      onProgress: onProgress,
    );
  }

  Future<void> softDelete(String bookmarkId) async {
    final Bookmark? bookmark = await findById(bookmarkId);
    if (bookmark == null || bookmark.isDeleted) return;
    final DateTime now = DateTime.now().toUtc();

    final Bookmark deleted = bookmark.copyWith(deletedAt: now, updatedAt: now);
    await _writeBookmarkAndOutbox(
      bookmark: deleted,
      opType: SyncOpType.delete,
      tombstoneAt: now,
    );
  }

  Future<int> softDeleteMany(List<String> bookmarkIds) async {
    final List<String> ids = _distinctIds(bookmarkIds);
    if (ids.isEmpty) return 0;

    final List<Bookmark> candidates = await _loadBookmarksByIds(
      ids,
      includeDeleted: false,
    );
    if (candidates.isEmpty) return 0;

    final DateTime now = DateTime.now().toUtc();
    int affected = 0;
    await _db.transaction((Transaction txn) async {
      for (final Bookmark bookmark in candidates) {
        final Bookmark deleted = bookmark.copyWith(
          deletedAt: now,
          updatedAt: now,
        );
        await _writeBookmarkAndOutbox(
          bookmark: deleted,
          opType: SyncOpType.delete,
          tombstoneAt: now,
          executor: txn,
        );
        affected += 1;
      }
    });
    return affected;
  }

  Future<Bookmark?> restoreFromTrash(String bookmarkId) async {
    final Bookmark? bookmark = await findById(bookmarkId);
    if (bookmark == null || !bookmark.isDeleted) return bookmark;
    final DateTime now = DateTime.now().toUtc();
    final Bookmark restored = bookmark.copyWith(
      deletedAt: null,
      updatedAt: now,
    );
    await _writeBookmarkAndOutbox(
      bookmark: restored,
      opType: SyncOpType.upsert,
      clearTombstone: true,
    );
    return restored;
  }

  Future<int> restoreFromTrashMany(List<String> bookmarkIds) async {
    final List<String> ids = _distinctIds(bookmarkIds);
    if (ids.isEmpty) return 0;

    final List<Bookmark> candidates = await _loadBookmarksByIds(
      ids,
      includeDeleted: true,
    );
    final List<Bookmark> deletedOnes = candidates
        .where((Bookmark b) => b.isDeleted)
        .toList();
    if (deletedOnes.isEmpty) return 0;

    final DateTime now = DateTime.now().toUtc();
    int affected = 0;
    await _db.transaction((Transaction txn) async {
      for (final Bookmark bookmark in deletedOnes) {
        final Bookmark restored = bookmark.copyWith(
          deletedAt: null,
          updatedAt: now,
        );
        await _writeBookmarkAndOutbox(
          bookmark: restored,
          opType: SyncOpType.upsert,
          clearTombstone: true,
          executor: txn,
        );
        affected += 1;
      }
    });
    return affected;
  }

  Future<int> emptyTrash() async {
    final List<Map<String, Object?>> rows = await _db.query(
      'bookmarks',
      columns: <String>['id'],
      where: 'deleted_at IS NOT NULL',
    );
    if (rows.isEmpty) {
      return 0;
    }
    final Batch batch = _db.batch();
    for (final Map<String, Object?> row in rows) {
      batch.delete(
        'bookmarks',
        where: 'id = ?',
        whereArgs: <Object?>[row['id']],
      );
    }
    await batch.commit(noResult: true);
    return rows.length;
  }

  Future<DedupResult> deduplicate({
    bool removeExact = true,
    bool removeSimilar = true,
  }) async {
    if (!removeExact && !removeSimilar) {
      return const DedupResult(exactRemoved: 0, similarRemoved: 0);
    }

    final List<Bookmark> active = await listBookmarks();
    if (active.length < 2) {
      return const DedupResult(exactRemoved: 0, similarRemoved: 0);
    }

    final List<Bookmark> ordered = List<Bookmark>.from(active)
      ..sort((Bookmark a, Bookmark b) => b.updatedAt.compareTo(a.updatedAt));

    final Set<String> removedIds = <String>{};
    int exactRemoved = 0;
    int similarRemoved = 0;
    final DateTime now = DateTime.now().toUtc();

    await _db.transaction((Transaction txn) async {
      if (removeExact) {
        final Map<String, Bookmark> keptByExactKey = <String, Bookmark>{};
        for (final Bookmark b in ordered) {
          final String key = _exactKey(b.normalizedUrl);
          if (keptByExactKey.containsKey(key)) {
            final Bookmark deleted = b.copyWith(deletedAt: now, updatedAt: now);
            await _writeBookmarkAndOutbox(
              bookmark: deleted,
              opType: SyncOpType.delete,
              tombstoneAt: now,
              executor: txn,
            );
            removedIds.add(b.id);
            exactRemoved += 1;
          } else {
            keptByExactKey[key] = b;
          }
        }
      }

      if (removeSimilar) {
        final Map<String, List<_SimilarEntry>> buckets =
            <String, List<_SimilarEntry>>{};
        for (final Bookmark b in ordered) {
          if (removedIds.contains(b.id)) continue;

          final _SimilarEntry candidate = _buildSimilarEntry(b.url);
          final List<_SimilarEntry> bucket = buckets.putIfAbsent(
            candidate.bucket,
            () => <_SimilarEntry>[],
          );
          final bool matched = bucket.any(
            (_SimilarEntry kept) => _isSimilarEntry(candidate, kept),
          );

          if (matched) {
            final Bookmark deleted = b.copyWith(deletedAt: now, updatedAt: now);
            await _writeBookmarkAndOutbox(
              bookmark: deleted,
              opType: SyncOpType.delete,
              tombstoneAt: now,
              executor: txn,
            );
            removedIds.add(b.id);
            similarRemoved += 1;
          } else {
            bucket.add(candidate);
          }
        }
      }
    });

    return DedupResult(
      exactRemoved: exactRemoved,
      similarRemoved: similarRemoved,
    );
  }

  Future<int> permanentlyDeleteFromTrashMany(List<String> bookmarkIds) async {
    final List<String> ids = _distinctIds(bookmarkIds);
    if (ids.isEmpty) return 0;

    int affected = 0;
    await _db.transaction((Transaction txn) async {
      for (final String id in ids) {
        final int deleted = await txn.delete(
          'bookmarks',
          where: 'id = ? AND deleted_at IS NOT NULL',
          whereArgs: <Object?>[id],
        );
        affected += deleted;
      }
    });
    return affected;
  }

  Future<void> clearAllData() async {
    await _db.transaction((Transaction txn) async {
      await txn.delete('bookmarks');
      await txn.delete('sync_outbox');
      await txn.delete('sync_state');
      await txn.delete('sync_tombstones');
    });
  }

  @override
  Future<List<SyncOp>> loadPendingOps() async {
    final List<Map<String, Object?>> rows = await _db.query(
      'sync_outbox',
      where: 'pushed = 0',
      orderBy: 'occurred_at ASC',
    );

    return rows.map((Map<String, Object?> row) {
      return SyncOp(
        opId: row['op_id']! as String,
        type: SyncOpType.values.firstWhere(
          (SyncOpType t) => t.name == row['op_type']! as String,
        ),
        bookmark: Bookmark.fromJson(
          jsonDecode(row['bookmark_json']! as String) as Map<String, dynamic>,
        ),
        occurredAt: DateTime.parse(row['occurred_at']! as String).toUtc(),
        deviceId: row['device_id']! as String,
      );
    }).toList();
  }

  @override
  Future<void> markOpsAsPushed(List<String> opIds) async {
    if (opIds.isEmpty) return;
    final Batch batch = _db.batch();
    for (final String opId in opIds) {
      batch.update(
        'sync_outbox',
        <String, Object?>{'pushed': 1},
        where: 'op_id = ?',
        whereArgs: <Object?>[opId],
      );
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<DateTime> lastPulledAt() async {
    final List<Map<String, Object?>> rows = await _db.query(
      'sync_state',
      where: 'key = ?',
      whereArgs: <Object?>['last_pulled_at'],
      limit: 1,
    );
    if (rows.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
    return DateTime.parse(rows.first['value']! as String).toUtc();
  }

  @override
  Future<void> saveLastPulledAt(DateTime timestamp) async {
    await _db.insert('sync_state', <String, Object?>{
      'key': 'last_pulled_at',
      'value': timestamp.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> upsertBookmark(Bookmark incoming) async {
    final Bookmark? local = await findById(incoming.id);
    final Bookmark merged = _merge(local, incoming);
    await _db.transaction((Transaction txn) async {
      await _upsertBookmarkLocal(merged, executor: txn);
      if (merged.deletedAt == null) {
        await _deleteTombstoneLocal(merged.id, executor: txn);
      } else {
        await _upsertTombstoneLocal(
          merged.id,
          merged.deletedAt!,
          executor: txn,
        );
      }
    });
  }

  @override
  Future<void> deleteBookmark(String bookmarkId) async {
    await _db.transaction((Transaction txn) async {
      await txn.delete(
        'bookmarks',
        where: 'id = ?',
        whereArgs: <Object?>[bookmarkId],
      );

      final List<Map<String, Object?>> pending = await txn.query(
        'sync_outbox',
        columns: <String>['op_id', 'bookmark_json'],
        where: 'pushed = 0',
      );
      for (final Map<String, Object?> row in pending) {
        final String raw = row['bookmark_json']! as String;
        try {
          final Map<String, dynamic> json =
              jsonDecode(raw) as Map<String, dynamic>;
          final String id = (json['id'] as String?)?.trim() ?? '';
          if (id != bookmarkId) continue;
          await txn.delete(
            'sync_outbox',
            where: 'op_id = ?',
            whereArgs: <Object?>[row['op_id']],
          );
        } catch (_) {
          continue;
        }
      }
    });
  }

  Future<void> _enqueueOp(
    SyncOpType type,
    Bookmark bookmark, {
    DatabaseExecutor? executor,
  }) async {
    final DateTime now = DateTime.now().toUtc();
    await (executor ?? _db).insert('sync_outbox', <String, Object?>{
      'op_id': _uuid.v4(),
      'op_type': type.name,
      'bookmark_json': jsonEncode(bookmark.toJson()),
      'occurred_at': now.toIso8601String(),
      'device_id': _deviceId,
      'pushed': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _writeBookmarkAndOutbox({
    required Bookmark bookmark,
    required SyncOpType opType,
    DateTime? tombstoneAt,
    bool clearTombstone = false,
    DatabaseExecutor? executor,
  }) async {
    Future<void> write(DatabaseExecutor dbExecutor) async {
      await _upsertBookmarkLocal(bookmark, executor: dbExecutor);
      if (tombstoneAt != null) {
        await _upsertTombstoneLocal(
          bookmark.id,
          tombstoneAt,
          executor: dbExecutor,
        );
      } else if (clearTombstone) {
        await _deleteTombstoneLocal(bookmark.id, executor: dbExecutor);
      }
      await _enqueueOp(opType, bookmark, executor: dbExecutor);
    }

    if (executor != null) {
      await write(executor);
      return;
    }

    await _db.transaction((Transaction txn) async {
      await write(txn);
    });
  }

  Future<void> _upsertBookmarkLocal(
    Bookmark bookmark, {
    DatabaseExecutor? executor,
  }) async {
    await (executor ?? _db).insert('bookmarks', <String, Object?>{
      'id': bookmark.id,
      'url': bookmark.url,
      'normalized_url': bookmark.normalizedUrl,
      'title': bookmark.title,
      'note': bookmark.note,
      'tags_json': jsonEncode(bookmark.tags),
      'created_at': bookmark.createdAt.toUtc().toIso8601String(),
      'updated_at': bookmark.updatedAt.toUtc().toIso8601String(),
      'deleted_at': bookmark.deletedAt?.toUtc().toIso8601String(),
      'title_updated_at': bookmark.titleUpdatedAt?.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _upsertTombstoneLocal(
    String bookmarkId,
    DateTime deletedAt, {
    DatabaseExecutor? executor,
  }) async {
    final DateTime deletedUtc = deletedAt.toUtc();
    final DateTime expireAt = deletedUtc.add(_tombstoneRetention);
    await (executor ?? _db).insert('sync_tombstones', <String, Object?>{
      'bookmark_id': bookmarkId,
      'deleted_at': deletedUtc.toIso8601String(),
      'expire_at': expireAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _deleteTombstoneLocal(
    String bookmarkId, {
    DatabaseExecutor? executor,
  }) async {
    await (executor ?? _db).delete(
      'sync_tombstones',
      where: 'bookmark_id = ?',
      whereArgs: <Object?>[bookmarkId],
    );
  }

  Bookmark _bookmarkFromRow(Map<String, Object?> row) {
    return Bookmark(
      id: row['id']! as String,
      url: row['url']! as String,
      normalizedUrl: row['normalized_url']! as String,
      title: row['title'] as String?,
      note: row['note'] as String?,
      tags: (jsonDecode(row['tags_json']! as String) as List<dynamic>)
          .map((dynamic e) => e.toString())
          .toList(),
      createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
      updatedAt: DateTime.parse(row['updated_at']! as String).toUtc(),
      deletedAt: (row['deleted_at'] as String?) == null
          ? null
          : DateTime.parse(row['deleted_at']! as String).toUtc(),
      titleUpdatedAt: (row['title_updated_at'] as String?) == null
          ? null
          : DateTime.parse(row['title_updated_at']! as String).toUtc(),
    );
  }

  Bookmark _merge(Bookmark? local, Bookmark incoming) {
    if (local == null) return incoming;

    final DateTime? localDeletedAt = local.deletedAt;
    final DateTime? incomingDeletedAt = incoming.deletedAt;

    if (incomingDeletedAt != null &&
        (localDeletedAt == null || incomingDeletedAt.isAfter(localDeletedAt))) {
      return incoming;
    }

    if (localDeletedAt != null &&
        (incomingDeletedAt == null ||
            !incomingDeletedAt.isAfter(localDeletedAt))) {
      return local;
    }

    if (incoming.updatedAt.isAfter(local.updatedAt)) {
      return incoming;
    }

    return local;
  }

  Future<int> _refreshTitlesInParallel(
    List<Bookmark> targets, {
    required int maxConcurrent,
    void Function(int processed, int total, int updated)? onProgress,
  }) async {
    if (targets.isEmpty) {
      onProgress?.call(0, 0, 0);
      return 0;
    }

    final int workerCount = maxConcurrent < 1
        ? 1
        : (maxConcurrent > 16 ? 16 : maxConcurrent);
    int nextIndex = 0;
    int updatedCount = 0;
    int processedCount = 0;
    final int total = targets.length;

    Future<void> worker() async {
      while (true) {
        if (nextIndex >= targets.length) {
          break;
        }
        final Bookmark target = targets[nextIndex];
        nextIndex += 1;

        try {
          final UrlMetadata metadata = await _metadataService.fetchTitle(
            target.url,
          );
          final DateTime now = DateTime.now().toUtc();
          final Bookmark updated = target.copyWith(
            title: metadata.title ?? target.title,
            note: null,
            titleUpdatedAt: now,
            updatedAt: now,
          );
          await _writeBookmarkAndOutbox(
            bookmark: updated,
            opType: SyncOpType.upsert,
          );
          updatedCount += 1;
        } on MetadataFetchException catch (e) {
          final DateTime now = DateTime.now().toUtc();
          final Bookmark failed = target.copyWith(
            note: buildTitleFetchFailureNote(e.message),
            titleUpdatedAt: now,
            updatedAt: now,
          );
          await _writeBookmarkAndOutbox(
            bookmark: failed,
            opType: SyncOpType.upsert,
          );
        } catch (_) {
          final DateTime now = DateTime.now().toUtc();
          final Bookmark failed = target.copyWith(
            note: buildTitleFetchFailureNote('无法连接该链接，请检查是否可访问'),
            titleUpdatedAt: now,
            updatedAt: now,
          );
          await _writeBookmarkAndOutbox(
            bookmark: failed,
            opType: SyncOpType.upsert,
          );
        }

        processedCount += 1;
        onProgress?.call(processedCount, total, updatedCount);
      }
    }

    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );
    return updatedCount;
  }

  Future<List<Bookmark>> _loadBookmarksByIds(
    List<String> ids, {
    required bool includeDeleted,
  }) async {
    final List<Bookmark> result = <Bookmark>[];
    for (final String id in ids) {
      final Bookmark? item = await findById(id);
      if (item == null) continue;
      if (!includeDeleted && item.isDeleted) continue;
      result.add(item);
    }
    return result;
  }

  List<String> _distinctIds(List<String> rawIds) {
    final Set<String> seen = <String>{};
    final List<String> result = <String>[];
    for (final String id in rawIds) {
      final String trimmed = id.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed)) {
        result.add(trimmed);
      }
    }
    return result;
  }

  String _normalizeUrl(String rawInput) {
    final String trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      throw FormatException('URL 不能为空');
    }

    Uri uri = Uri.parse(trimmed);
    if (!uri.hasScheme) {
      uri = Uri.parse('https://$trimmed');
    }

    if (!(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw FormatException('仅支持 http/https URL');
    }

    return uri.normalizePath().toString();
  }

  String _exactKey(String rawUrl) {
    final Uri uri = _safeUri(rawUrl);
    final String scheme = uri.scheme.toLowerCase();
    final String host = uri.host.toLowerCase();
    final int? port = uri.hasPort ? uri.port : null;
    final bool isDefaultPort =
        (scheme == 'http' && port == 80) || (scheme == 'https' && port == 443);
    final String portPart = (port == null || isDefaultPort)
        ? ''
        : ':${port.toString()}';

    String path = uri.path.toLowerCase();
    if (path.isEmpty) {
      path = '/';
    } else if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    final List<MapEntry<String, String>> query =
        uri.queryParametersAll.entries
            .expand(
              (MapEntry<String, List<String>> e) => e.value.isEmpty
                  ? <MapEntry<String, String>>[
                      MapEntry<String, String>(e.key.toLowerCase(), ''),
                    ]
                  : e.value.map(
                      (String v) =>
                          MapEntry<String, String>(e.key.toLowerCase(), v),
                    ),
            )
            .toList()
          ..sort((MapEntry<String, String> a, MapEntry<String, String> b) {
            final int keyCmp = a.key.compareTo(b.key);
            if (keyCmp != 0) return keyCmp;
            return a.value.compareTo(b.value);
          });

    final String queryPart = query.isEmpty
        ? ''
        : '?${query.map((MapEntry<String, String> e) => '${e.key}=${e.value}').join('&')}';

    return '$scheme://$host$portPart$path$queryPart';
  }

  _SimilarEntry _buildSimilarEntry(String rawUrl) {
    final Uri uri = _safeUri(rawUrl);

    String host = uri.host.toLowerCase();
    if (host.startsWith('www.')) {
      host = host.substring(4);
    } else if (host.startsWith('m.')) {
      host = host.substring(2);
    } else if (host.startsWith('mobile.')) {
      host = host.substring('mobile.'.length);
    }

    String path = uri.path.toLowerCase();
    if (path.isEmpty) {
      path = '/';
    } else if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    final List<String> pathSegments = path
        .split('/')
        .map((String s) => s.trim().toLowerCase())
        .where((String s) => s.isNotEmpty)
        .toList();
    final String firstPath = pathSegments.isEmpty ? '/' : pathSegments.first;
    final Set<String> pathTokens = _urlTokens(path);

    final List<MapEntry<String, String>> nonTrackingQuery =
        uri.queryParametersAll.entries
            .where(
              (MapEntry<String, List<String>> e) =>
                  !_trackingQueryKeys.contains(e.key.toLowerCase()),
            )
            .expand(
              (MapEntry<String, List<String>> e) => e.value.isEmpty
                  ? <MapEntry<String, String>>[
                      MapEntry<String, String>(e.key.toLowerCase(), ''),
                    ]
                  : e.value.map(
                      (String v) =>
                          MapEntry<String, String>(e.key.toLowerCase(), v),
                    ),
            )
            .toList()
          ..sort((MapEntry<String, String> a, MapEntry<String, String> b) {
            final int keyCmp = a.key.compareTo(b.key);
            if (keyCmp != 0) return keyCmp;
            return a.value.compareTo(b.value);
          });

    final String queryPart = nonTrackingQuery.isEmpty
        ? ''
        : '?${nonTrackingQuery.map((MapEntry<String, String> e) => '${e.key}=${e.value}').join('&')}';
    final String canonical = '$host$path$queryPart';

    final Set<String> tokens = <String>{...pathTokens, ..._urlTokens(queryPart)}
      ..add(host);

    return _SimilarEntry(
      bucket: '$host|$firstPath',
      canonical: canonical,
      tokens: tokens,
    );
  }

  bool _isSimilarEntry(_SimilarEntry a, _SimilarEntry b) {
    if (a.canonical == b.canonical) {
      return true;
    }

    if (a.canonical.length >= 12 &&
        b.canonical.length >= 12 &&
        (a.canonical.contains(b.canonical) ||
            b.canonical.contains(a.canonical))) {
      return true;
    }

    final double tokenScore = _jaccardScore(a.tokens, b.tokens);
    if (tokenScore >= 0.82) {
      return true;
    }

    final double textScore = _normalizedLevenshteinScore(
      a.canonical,
      b.canonical,
    );
    return textScore >= 0.9;
  }

  Set<String> _urlTokens(String input) {
    return input
        .split(RegExp(r'[^a-z0-9]+'))
        .map((String t) => t.trim())
        .where((String t) => t.isNotEmpty)
        .toSet();
  }

  double _jaccardScore(Set<String> a, Set<String> b) {
    if (a.isEmpty && b.isEmpty) {
      return 1;
    }
    final Set<String> intersection = a.intersection(b);
    final Set<String> union = <String>{...a, ...b};
    if (union.isEmpty) return 0;
    return intersection.length / union.length;
  }

  double _normalizedLevenshteinScore(String a, String b) {
    if (a == b) return 1;
    if (a.isEmpty || b.isEmpty) return 0;

    final int distance = _levenshteinDistance(a, b);
    final int maxLen = a.length > b.length ? a.length : b.length;
    return 1 - (distance / maxLen);
  }

  int _levenshteinDistance(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final List<int> previous = List<int>.generate(b.length + 1, (int i) => i);
    final List<int> current = List<int>.filled(b.length + 1, 0);

    for (int i = 1; i <= a.length; i += 1) {
      current[0] = i;
      for (int j = 1; j <= b.length; j += 1) {
        final int cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        final int deletion = previous[j] + 1;
        final int insertion = current[j - 1] + 1;
        final int substitution = previous[j - 1] + cost;
        int best = deletion < insertion ? deletion : insertion;
        if (substitution < best) {
          best = substitution;
        }
        current[j] = best;
      }

      for (int j = 0; j <= b.length; j += 1) {
        previous[j] = current[j];
      }
    }

    return previous[b.length];
  }

  Uri _safeUri(String rawUrl) {
    final String input = rawUrl.trim();
    try {
      Uri uri = Uri.parse(input);
      if (!uri.hasScheme) {
        uri = Uri.parse('https://$input');
      }
      return uri;
    } catch (_) {
      final String fallback = input.toLowerCase();
      return Uri(
        scheme: 'https',
        host: 'invalid.local',
        path: fallback.isEmpty ? '/' : '/${Uri.encodeComponent(fallback)}',
      );
    }
  }
}

class _SimilarEntry {
  const _SimilarEntry({
    required this.bucket,
    required this.canonical,
    required this.tokens,
  });

  final String bucket;
  final String canonical;
  final Set<String> tokens;
}

const Set<String> _trackingQueryKeys = <String>{
  'utm_source',
  'utm_medium',
  'utm_campaign',
  'utm_term',
  'utm_content',
  'utm_id',
  'utm_name',
  'utm_cid',
  'utm_reader',
  'utm_viz_id',
  'utm_pubreferrer',
  'utm_swu',
  'gclid',
  'fbclid',
  'igshid',
  'msclkid',
  'ref',
  'ref_src',
  'source',
};
