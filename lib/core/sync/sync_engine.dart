import '../domain/bookmark.dart';
import 'sync_provider.dart';
import 'sync_types.dart';

abstract class LocalStore {
  Future<List<SyncOp>> loadPendingOps();
  Future<void> markOpsAsPushed(List<String> opIds);
  Future<DateTime> lastPulledAt();
  Future<void> saveLastPulledAt(DateTime timestamp);
  Future<List<String>> lastPulledPathsAtCursor() async => const <String>[];
  Future<void> saveLastPulledCursor({
    required DateTime timestamp,
    required List<String> pathsAtTimestamp,
  }) async {
    await saveLastPulledAt(timestamp);
  }

  Future<Bookmark?> findBookmarkById(String bookmarkId);
  Future<DateTime?> findTombstoneAt(String bookmarkId);
  Future<void> saveTombstone(String bookmarkId, DateTime deletedAt);
  Future<void> clearTombstone(String bookmarkId);
  Future<void> upsertBookmark(Bookmark bookmark);
  Future<void> deleteBookmark(String bookmarkId);
}

class SyncEngineReport {
  const SyncEngineReport({
    required this.localPendingOps,
    required this.pushedOps,
    required this.pulledBatchCount,
    required this.pulledOps,
    required this.filteredSelfDeviceOps,
    required this.filteredDuplicateOps,
    required this.filteredStaleOps,
    required this.appliedUpserts,
    required this.appliedDeletes,
    required this.cursorBefore,
    required this.cursorAfter,
  });

  final int localPendingOps;
  final int pushedOps;
  final int pulledBatchCount;
  final int pulledOps;
  final int filteredSelfDeviceOps;
  final int filteredDuplicateOps;
  final int filteredStaleOps;
  final int appliedUpserts;
  final int appliedDeletes;
  final DateTime cursorBefore;
  final DateTime cursorAfter;
}

class SyncEngine {
  SyncEngine({
    required this.localStore,
    required this.syncProvider,
    required this.userId,
    required this.deviceId,
  });

  final LocalStore localStore;
  final SyncProvider syncProvider;
  final String userId;
  final String deviceId;

  Future<SyncEngineReport> syncOnce() async {
    final List<SyncOp> localOps = await localStore.loadPendingOps();
    final int pendingOpsCount = localOps.length;
    if (localOps.isNotEmpty) {
      await syncProvider.pushOps(
        userId: userId,
        deviceId: deviceId,
        ops: localOps,
      );
      await localStore.markOpsAsPushed(
        localOps.map((SyncOp e) => e.opId).toList(),
      );
    }

    final DateTime since = await localStore.lastPulledAt();
    final Set<String> pathsAtCursor =
        (await localStore.lastPulledPathsAtCursor())
            .map((String path) => path.trim())
            .where((String path) => path.isNotEmpty)
            .toSet();
    final List<PulledSyncBatch> remoteBatches = await syncProvider.pullOpsSince(
      userId: userId,
      since: since,
      pathsAtCursor: pathsAtCursor,
    );

    DateTime maxPulled = since;
    final Set<String> maxCursorPaths = <String>{...pathsAtCursor};
    final Set<String> seenOpIds = <String>{};
    final Map<String, SyncOp> latestByBookmarkId = <String, SyncOp>{};
    int pulledOpsCount = 0;
    int filteredSelfDeviceOps = 0;
    int filteredDuplicateOps = 0;
    for (final PulledSyncBatch pulled in remoteBatches) {
      pulledOpsCount += pulled.batch.ops.length;
      for (final SyncOp op in pulled.batch.ops) {
        if (op.deviceId == deviceId) {
          filteredSelfDeviceOps += 1;
          continue;
        }
        if (!seenOpIds.add(op.opId)) {
          filteredDuplicateOps += 1;
          continue;
        }
        final String bookmarkId = op.bookmark.id;
        final SyncOp? current = latestByBookmarkId[bookmarkId];
        if (current == null || _compareOpFreshness(op, current) > 0) {
          latestByBookmarkId[bookmarkId] = op;
        }
      }
      if (pulled.cursorAt.isAfter(maxPulled)) {
        maxPulled = pulled.cursorAt;
        maxCursorPaths
          ..clear()
          ..add(pulled.sourcePath);
      } else if (pulled.cursorAt.isAtSameMomentAs(maxPulled)) {
        maxCursorPaths.add(pulled.sourcePath);
      }
    }

    final List<SyncOp> latestOps = latestByBookmarkId.values.toList()
      ..sort((SyncOp a, SyncOp b) {
        final int byTime = _logicalTimestamp(a).compareTo(_logicalTimestamp(b));
        if (byTime != 0) {
          return byTime;
        }
        return a.opId.compareTo(b.opId);
      });
    int filteredStaleOps = 0;
    int appliedDeletes = 0;
    int appliedUpserts = 0;
    for (final SyncOp op in latestOps) {
      final Bookmark? local = await localStore.findBookmarkById(op.bookmark.id);
      final DateTime? tombstoneAt = await localStore.findTombstoneAt(
        op.bookmark.id,
      );
      if (!_shouldApplyRemoteOp(local, tombstoneAt, op)) {
        filteredStaleOps += 1;
        continue;
      }
      if (op.type == SyncOpType.delete || op.bookmark.isDeleted) {
        final DateTime deletedAt = _logicalTimestamp(op);
        await localStore.saveTombstone(op.bookmark.id, deletedAt);
        await localStore.deleteBookmark(op.bookmark.id);
        appliedDeletes += 1;
        continue;
      }
      await localStore.upsertBookmark(_applyMergePolicy(op.bookmark));
      await localStore.clearTombstone(op.bookmark.id);
      appliedUpserts += 1;
    }

    await localStore.saveLastPulledCursor(
      timestamp: maxPulled,
      pathsAtTimestamp: maxCursorPaths.toList()..sort(),
    );
    return SyncEngineReport(
      localPendingOps: pendingOpsCount,
      pushedOps: pendingOpsCount,
      pulledBatchCount: remoteBatches.length,
      pulledOps: pulledOpsCount,
      filteredSelfDeviceOps: filteredSelfDeviceOps,
      filteredDuplicateOps: filteredDuplicateOps,
      filteredStaleOps: filteredStaleOps,
      appliedUpserts: appliedUpserts,
      appliedDeletes: appliedDeletes,
      cursorBefore: since,
      cursorAfter: maxPulled,
    );
  }

  Bookmark _applyMergePolicy(Bookmark incoming) {
    // MVP：此处仅做透传。实际需要与本地记录比较 updatedAt/deletedAt 后再决定。
    return incoming;
  }

  int _compareOpFreshness(SyncOp a, SyncOp b) {
    final DateTime timeA = _logicalTimestamp(a);
    final DateTime timeB = _logicalTimestamp(b);
    final int byTime = timeA.compareTo(timeB);
    if (byTime != 0) {
      return byTime;
    }
    final bool deleteA = _isDeleteLike(a);
    final bool deleteB = _isDeleteLike(b);
    if (deleteA != deleteB) {
      return deleteA ? 1 : -1;
    }
    return a.opId.compareTo(b.opId);
  }

  DateTime _logicalTimestamp(SyncOp op) {
    final DateTime updatedAt = op.bookmark.updatedAt;
    final DateTime? deletedAt = op.bookmark.deletedAt;
    if (deletedAt != null && deletedAt.isAfter(updatedAt)) {
      return deletedAt;
    }
    return updatedAt;
  }

  bool _shouldApplyRemoteOp(
    Bookmark? local,
    DateTime? tombstoneAt,
    SyncOp remote,
  ) {
    final DateTime remoteAt = _logicalTimestamp(remote);
    if (tombstoneAt != null) {
      if (remoteAt.isBefore(tombstoneAt)) {
        return false;
      }
      if (remoteAt.isAtSameMomentAs(tombstoneAt) && !_isDeleteLike(remote)) {
        return false;
      }
    }

    if (local == null) {
      return true;
    }
    final DateTime localAt = _localLogicalTimestamp(local);
    if (remoteAt.isAfter(localAt)) {
      return true;
    }
    if (remoteAt.isBefore(localAt)) {
      return false;
    }
    if (_isDeleteLike(remote) && !local.isDeleted) {
      return true;
    }
    return false;
  }

  DateTime _localLogicalTimestamp(Bookmark local) {
    final DateTime? deletedAt = local.deletedAt;
    if (deletedAt != null && deletedAt.isAfter(local.updatedAt)) {
      return deletedAt;
    }
    return local.updatedAt;
  }

  bool _isDeleteLike(SyncOp op) {
    return op.type == SyncOpType.delete || op.bookmark.isDeleted;
  }
}
