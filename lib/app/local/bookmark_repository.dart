import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/domain/bookmark.dart';
import '../../core/metadata/metadata_fetch_service.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_types.dart';

class DedupResult {
  const DedupResult({
    required this.exactRemoved,
    required this.similarRemoved,
  });

  final int exactRemoved;
  final int similarRemoved;

  int get totalRemoved => exactRemoved + similarRemoved;
}

class BookmarkRepository implements LocalStore {
  BookmarkRepository({
    required Database db,
    required MetadataFetchService metadataService,
    required String deviceId,
  })  : _db = db,
        _metadataService = metadataService,
        _deviceId = deviceId;

  final Database _db;
  final MetadataFetchService _metadataService;
  final String _deviceId;
  final Uuid _uuid = const Uuid();

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

    await _upsertBookmarkLocal(bookmark);
    await _enqueueOp(SyncOpType.upsert, bookmark);

    return bookmark;
  }

  Future<Bookmark?> refreshTitle(String bookmarkId) async {
    final Bookmark? bookmark = await findById(bookmarkId);
    if (bookmark == null || bookmark.isDeleted) return null;

    final UrlMetadata metadata = await _metadataService.fetchTitle(
      bookmark.url,
    );
    final DateTime now = DateTime.now().toUtc();

    final Bookmark updated = bookmark.copyWith(
      title: metadata.title ?? bookmark.title,
      titleUpdatedAt: now,
      updatedAt: now,
    );

    await _upsertBookmarkLocal(updated);
    await _enqueueOp(SyncOpType.upsert, updated);
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

    await _upsertBookmarkLocal(deleted);
    await _enqueueOp(SyncOpType.delete, deleted);
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
        final Bookmark deleted =
            bookmark.copyWith(deletedAt: now, updatedAt: now);
        await _upsertBookmarkLocal(deleted, executor: txn);
        await _enqueueOp(SyncOpType.delete, deleted, executor: txn);
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
    await _upsertBookmarkLocal(restored);
    await _enqueueOp(SyncOpType.upsert, restored);
    return restored;
  }

  Future<int> restoreFromTrashMany(List<String> bookmarkIds) async {
    final List<String> ids = _distinctIds(bookmarkIds);
    if (ids.isEmpty) return 0;

    final List<Bookmark> candidates = await _loadBookmarksByIds(
      ids,
      includeDeleted: true,
    );
    final List<Bookmark> deletedOnes =
        candidates.where((Bookmark b) => b.isDeleted).toList();
    if (deletedOnes.isEmpty) return 0;

    final DateTime now = DateTime.now().toUtc();
    int affected = 0;
    await _db.transaction((Transaction txn) async {
      for (final Bookmark bookmark in deletedOnes) {
        final Bookmark restored =
            bookmark.copyWith(deletedAt: null, updatedAt: now);
        await _upsertBookmarkLocal(restored, executor: txn);
        await _enqueueOp(SyncOpType.upsert, restored, executor: txn);
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
          final String key = b.normalizedUrl.toLowerCase().trim();
          if (keptByExactKey.containsKey(key)) {
            final Bookmark deleted = b.copyWith(deletedAt: now, updatedAt: now);
            await _upsertBookmarkLocal(deleted, executor: txn);
            await _enqueueOp(SyncOpType.delete, deleted, executor: txn);
            removedIds.add(b.id);
            exactRemoved += 1;
          } else {
            keptByExactKey[key] = b;
          }
        }
      }

      if (removeSimilar) {
        final Map<String, Bookmark> keptBySimilarKey = <String, Bookmark>{};
        for (final Bookmark b in ordered) {
          if (removedIds.contains(b.id)) continue;
          final String key = _similarKey(b.url);
          if (keptBySimilarKey.containsKey(key)) {
            final Bookmark deleted = b.copyWith(deletedAt: now, updatedAt: now);
            await _upsertBookmarkLocal(deleted, executor: txn);
            await _enqueueOp(SyncOpType.delete, deleted, executor: txn);
            removedIds.add(b.id);
            similarRemoved += 1;
          } else {
            keptBySimilarKey[key] = b;
          }
        }
      }
    });

    return DedupResult(
        exactRemoved: exactRemoved, similarRemoved: similarRemoved);
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
    await _db.insert(
        'sync_state',
        <String, Object?>{
          'key': 'last_pulled_at',
          'value': timestamp.toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> upsertBookmark(Bookmark incoming) async {
    final Bookmark? local = await findById(incoming.id);
    final Bookmark merged = _merge(local, incoming);
    await _upsertBookmarkLocal(merged);
  }

  Future<void> _enqueueOp(
    SyncOpType type,
    Bookmark bookmark, {
    DatabaseExecutor? executor,
  }) async {
    final DateTime now = DateTime.now().toUtc();
    await (executor ?? _db).insert(
        'sync_outbox',
        <String, Object?>{
          'op_id': _uuid.v4(),
          'op_type': type.name,
          'bookmark_json': jsonEncode(bookmark.toJson()),
          'occurred_at': now.toIso8601String(),
          'device_id': _deviceId,
          'pushed': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _upsertBookmarkLocal(
    Bookmark bookmark, {
    DatabaseExecutor? executor,
  }) async {
    await (executor ?? _db).insert(
        'bookmarks',
        <String, Object?>{
          'id': bookmark.id,
          'url': bookmark.url,
          'normalized_url': bookmark.normalizedUrl,
          'title': bookmark.title,
          'note': bookmark.note,
          'tags_json': jsonEncode(bookmark.tags),
          'created_at': bookmark.createdAt.toUtc().toIso8601String(),
          'updated_at': bookmark.updatedAt.toUtc().toIso8601String(),
          'deleted_at': bookmark.deletedAt?.toUtc().toIso8601String(),
          'title_updated_at':
              bookmark.titleUpdatedAt?.toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
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

    final int workerCount =
        maxConcurrent < 1 ? 1 : (maxConcurrent > 16 ? 16 : maxConcurrent);
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
            titleUpdatedAt: now,
            updatedAt: now,
          );
          await _upsertBookmarkLocal(updated);
          await _enqueueOp(SyncOpType.upsert, updated);
          updatedCount += 1;
        } catch (_) {
          // 网络波动或目标站异常时，跳过单条继续处理剩余任务。
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

  String _similarKey(String rawUrl) {
    try {
      Uri uri = Uri.parse(rawUrl);
      if (!uri.hasScheme) {
        uri = Uri.parse('https://$rawUrl');
      }

      String host = uri.host.toLowerCase();
      if (host.startsWith('www.')) {
        host = host.substring(4);
      }

      String path = uri.path.toLowerCase();
      if (path.endsWith('/')) {
        path = path.substring(0, path.length - 1);
      }
      if (path.isEmpty) {
        path = '/';
      }

      return '$host$path';
    } catch (_) {
      return rawUrl.trim().toLowerCase();
    }
  }
}
