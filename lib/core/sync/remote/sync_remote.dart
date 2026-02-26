import '../sync_models.dart';

abstract interface class SyncRemote {
  Future<void> ensureInitialized({required String deviceId});

  Future<List<SyncChange>> pullChanges({
    required String currentDeviceId,
    required int limit,
    String? afterChangeId,
  });

  Future<SyncObject?> getObject({
    required String entityType,
    required String entityId,
  });

  Future<void> putObject(SyncObject object);

  Future<void> putChange(SyncChange change);

  Future<void> updateClientMeta({
    required String deviceId,
    required int lastSeenLamport,
    String? lastAppliedChangeId,
  });
}

class FakeSyncRemote implements SyncRemote {
  final Map<String, SyncObject> _objects = <String, SyncObject>{};
  final Map<String, SyncChange> _changes = <String, SyncChange>{};
  final Map<String, Map<String, Object?>> _clientMeta =
      <String, Map<String, Object?>>{};

  @override
  Future<void> ensureInitialized({required String deviceId}) async {
    _clientMeta.putIfAbsent(deviceId, () => <String, Object?>{});
  }

  @override
  Future<SyncObject?> getObject({
    required String entityType,
    required String entityId,
  }) async {
    return _objects['$entityType:$entityId'];
  }

  @override
  Future<List<SyncChange>> pullChanges({
    required String currentDeviceId,
    required int limit,
    String? afterChangeId,
  }) async {
    final List<SyncChange> all =
        _changes.values
            .where((SyncChange c) => c.deviceId != currentDeviceId)
            .toList(growable: false)
          ..sort((SyncChange a, SyncChange b) {
            final int byCreated = a.createdAt.compareTo(b.createdAt);
            if (byCreated != 0) {
              return byCreated;
            }
            return a.id.compareTo(b.id);
          });

    int start = 0;
    if (afterChangeId != null) {
      start = all.indexWhere((SyncChange c) => c.id == afterChangeId) + 1;
      if (start < 0) {
        start = 0;
      }
    }
    return all.skip(start).take(limit).toList(growable: false);
  }

  @override
  Future<void> putChange(SyncChange change) async {
    _changes[change.id] = change;
  }

  @override
  Future<void> putObject(SyncObject object) async {
    _objects['${object.entityType}:${object.entityId}'] = object;
  }

  @override
  Future<void> updateClientMeta({
    required String deviceId,
    required int lastSeenLamport,
    String? lastAppliedChangeId,
  }) async {
    _clientMeta[deviceId] = <String, Object?>{
      'last_seen_lamport': lastSeenLamport,
      'last_applied_change_id': lastAppliedChangeId,
    };
  }

  SyncObject? debugObject(String entityType, String entityId) {
    return _objects['$entityType:$entityId'];
  }

  int get debugChangeCount => _changes.length;

  bool debugHasChange(String changeId) => _changes.containsKey(changeId);
}
