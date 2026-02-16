import 'sync_types.dart';

abstract class SyncProvider {
  Future<void> pushOps({
    required String userId,
    required String deviceId,
    required List<SyncOp> ops,
  });

  Future<List<SyncBatch>> pullOpsSince({
    required String userId,
    required DateTime since,
  });
}
