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
    final List<SyncBatch> remoteBatches = await syncProvider.pullOpsSince(
      userId: userId,
      since: since,
    );

    DateTime maxPulled = since;
    for (final SyncBatch batch in remoteBatches) {
      for (final SyncOp op in batch.ops) {
        await localStore.upsertBookmark(_applyMergePolicy(op.bookmark));
      }
      if (batch.createdAt.isAfter(maxPulled)) {
        maxPulled = batch.createdAt;
      }
    }
    await localStore.saveLastPulledAt(maxPulled);
  }

  Bookmark _applyMergePolicy(Bookmark incoming) {
    // MVP：此处仅做透传。实际需要与本地记录比较 updatedAt/deletedAt 后再决定。
    return incoming;
  }
}
