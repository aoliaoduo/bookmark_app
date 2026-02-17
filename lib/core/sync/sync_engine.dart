import '../domain/bookmark.dart';
import 'sync_provider.dart';
import 'sync_types.dart';

abstract class LocalStore {
  Future<List<SyncOp>> loadPendingOps();
  Future<void> markOpsAsPushed(List<String> opIds);
  Future<DateTime> lastPulledAt();
  Future<void> saveLastPulledAt(DateTime timestamp);
  Future<Bookmark?> findBookmarkById(String bookmarkId);
  Future<void> upsertBookmark(Bookmark bookmark);
  Future<void> deleteBookmark(String bookmarkId);
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

  Future<void> syncOnce() async {
    final List<SyncOp> localOps = await localStore.loadPendingOps();
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
    final List<PulledSyncBatch> remoteBatches = await syncProvider.pullOpsSince(
      userId: userId,
      since: since,
    );

    DateTime maxPulled = since;
    final Set<String> seenOpIds = <String>{};
    final Map<String, SyncOp> latestByBookmarkId = <String, SyncOp>{};
    for (final PulledSyncBatch pulled in remoteBatches) {
      for (final SyncOp op in pulled.batch.ops) {
        if (op.deviceId == deviceId) {
          continue;
        }
        if (!seenOpIds.add(op.opId)) {
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
    for (final SyncOp op in latestOps) {
      final Bookmark? local = await localStore.findBookmarkById(op.bookmark.id);
      if (!_shouldApplyRemoteOp(local, op)) {
        continue;
      }
      if (op.type == SyncOpType.delete || op.bookmark.isDeleted) {
        await localStore.deleteBookmark(op.bookmark.id);
        continue;
      }
      await localStore.upsertBookmark(_applyMergePolicy(op.bookmark));
    }

    await localStore.saveLastPulledAt(maxPulled);
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
    final DateTime bookmarkUpdated = op.bookmark.updatedAt;
    final DateTime base = bookmarkUpdated.isAfter(op.occurredAt)
        ? bookmarkUpdated
        : op.occurredAt;
    final DateTime? deletedAt = op.bookmark.deletedAt;
    if (deletedAt != null && deletedAt.isAfter(base)) {
      return deletedAt;
    }
    return base;
  }

  bool _shouldApplyRemoteOp(Bookmark? local, SyncOp remote) {
    if (local == null) {
      return true;
    }
    final DateTime remoteAt = _logicalTimestamp(remote);
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
