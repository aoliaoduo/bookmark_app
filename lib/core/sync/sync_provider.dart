import 'sync_types.dart';

class PulledSyncBatch {
  const PulledSyncBatch({
    required this.batch,
    required this.cursorAt,
  });

  final SyncBatch batch;
  final DateTime cursorAt;
}

abstract class SyncProvider {
  Future<void> pushOps({
    required String userId,
    required String deviceId,
    required List<SyncOp> ops,
  });

  Future<List<PulledSyncBatch>> pullOpsSince({
    required String userId,
    required DateTime since,
  });
}
