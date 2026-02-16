import '../domain/bookmark.dart';
import 'sync_provider.dart';
import 'sync_types.dart';

abstract class LocalStore {
  Future<List<SyncOp>> loadPendingOps();
  Future<void> markOpsAsPushed(List<String> opIds);
  Future<DateTime> lastPulledAt();
  Future<void> saveLastPulledAt(DateTime timestamp);
  Future<void> upsertBookmark(Bookmark bookmark);
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
    final List<SyncOp> ignoredLocalOps =
        localOps.where((SyncOp op) => !_shouldSync(op)).toList(growable: false);
    if (ignoredLocalOps.isNotEmpty) {
      await localStore.markOpsAsPushed(
        ignoredLocalOps.map((SyncOp e) => e.opId).toList(),
      );
    }

    final List<SyncOp> syncableLocalOps =
        localOps.where(_shouldSync).toList(growable: false);
    if (syncableLocalOps.isNotEmpty) {
      await syncProvider.pushOps(
        userId: userId,
        deviceId: deviceId,
        ops: syncableLocalOps,
      );
      await localStore.markOpsAsPushed(
        syncableLocalOps.map((SyncOp e) => e.opId).toList(),
      );
    }

    final DateTime since = await localStore.lastPulledAt();
    final List<PulledSyncBatch> remoteBatches = await syncProvider.pullOpsSince(
      userId: userId,
      since: since,
    );

    DateTime maxPulled = since;
    for (final PulledSyncBatch pulled in remoteBatches) {
      for (final SyncOp op in pulled.batch.ops) {
        if (!_shouldSync(op)) {
          continue;
        }
        await localStore.upsertBookmark(_applyMergePolicy(op.bookmark));
      }
      if (pulled.cursorAt.isAfter(maxPulled)) {
        maxPulled = pulled.cursorAt;
      }
    }
    await localStore.saveLastPulledAt(maxPulled);
  }

  Bookmark _applyMergePolicy(Bookmark incoming) {
    // MVP：此处仅做透传。实际需要与本地记录比较 updatedAt/deletedAt 后再决定。
    return incoming;
  }

  bool _shouldSync(SyncOp op) {
    return op.type == SyncOpType.upsert && !op.bookmark.isDeleted;
  }
}
