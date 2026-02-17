import 'package:bookmark_app/core/domain/bookmark.dart';
import 'package:bookmark_app/core/sync/sync_engine.dart';
import 'package:bookmark_app/core/sync/sync_provider.dart';
import 'package:bookmark_app/core/sync/sync_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('syncOnce advances cursor by pulled cursorAt', () async {
    final DateTime since = DateTime.utc(2026, 2, 16, 11, 0, 0);
    final _FakeLocalStore local = _FakeLocalStore(
      pendingOps: const <SyncOp>[],
      lastPulled: since,
    );
    final SyncBatch batch = SyncBatch(
      deviceId: 'remote-device',
      createdAt: DateTime.utc(2020, 1, 1),
      ops: <SyncOp>[
        SyncOp(
          opId: 'op-1',
          type: SyncOpType.upsert,
          bookmark: _bookmark('b-1'),
          occurredAt: DateTime.utc(2026, 2, 16, 10, 0, 0),
          deviceId: 'remote-device',
        ),
      ],
    );
    final DateTime serverCursor = DateTime.utc(2026, 2, 16, 12, 0, 0);
    final _FakeSyncProvider provider = _FakeSyncProvider(
      pulled: <PulledSyncBatch>[
        PulledSyncBatch(batch: batch, cursorAt: serverCursor),
      ],
    );

    final SyncEngine engine = SyncEngine(
      localStore: local,
      syncProvider: provider,
      userId: 'u1',
      deviceId: 'd1',
    );

    await engine.syncOnce();

    expect(local.savedCursor, serverCursor);
    expect(local.markedOpIds, isEmpty);
    expect(local.upserted.length, 1);
    expect(local.upserted.single.id, 'b-1');
    expect(local.deletedIds, isEmpty);
  });

  test('syncOnce uploads deletes and applies pulled delete locally', () async {
    final DateTime now = DateTime.utc(2026, 2, 16, 12, 0, 0);
    final _FakeLocalStore local = _FakeLocalStore(
      pendingOps: <SyncOp>[
        SyncOp(
          opId: 'op-local-delete',
          type: SyncOpType.delete,
          bookmark: _bookmark('local-trash').copyWith(deletedAt: now),
          occurredAt: now,
          deviceId: 'local-device',
        ),
        SyncOp(
          opId: 'op-local-upsert',
          type: SyncOpType.upsert,
          bookmark: _bookmark('local-keep'),
          occurredAt: now,
          deviceId: 'local-device',
        ),
      ],
      lastPulled: DateTime.utc(2026, 2, 16, 11, 0, 0),
    );

    final SyncBatch batch = SyncBatch(
      deviceId: 'remote-device',
      createdAt: now,
      ops: <SyncOp>[
        SyncOp(
          opId: 'op-remote-delete',
          type: SyncOpType.delete,
          bookmark: _bookmark('remote-trash').copyWith(deletedAt: now),
          occurredAt: now,
          deviceId: 'remote-device',
        ),
        SyncOp(
          opId: 'op-remote-upsert',
          type: SyncOpType.upsert,
          bookmark: _bookmark('remote-keep'),
          occurredAt: now,
          deviceId: 'remote-device',
        ),
      ],
    );
    final _FakeSyncProvider provider = _FakeSyncProvider(
      pulled: <PulledSyncBatch>[
        PulledSyncBatch(batch: batch, cursorAt: DateTime.utc(2026, 2, 16, 13)),
      ],
    );

    final SyncEngine engine = SyncEngine(
      localStore: local,
      syncProvider: provider,
      userId: 'u1',
      deviceId: 'd1',
    );

    await engine.syncOnce();

    expect(provider.pushedOps.length, 2);
    expect(
      provider.pushedOps.map((SyncOp op) => op.opId).toSet(),
      <String>{'op-local-delete', 'op-local-upsert'},
    );
    expect(local.markedOpIds, <String>['op-local-delete', 'op-local-upsert']);
    expect(local.upserted.length, 1);
    expect(local.upserted.single.id, 'remote-keep');
    expect(local.deletedIds, <String>['remote-trash']);
  });

  test('syncOnce ignores same-device and duplicated pulled ops', () async {
    final DateTime now = DateTime.utc(2026, 2, 16, 12, 0, 0);
    final _FakeLocalStore local = _FakeLocalStore(
      pendingOps: const <SyncOp>[],
      lastPulled: DateTime.utc(2026, 2, 16, 11, 0, 0),
    );

    final SyncOp remoteUpsert = SyncOp(
      opId: 'remote-op-1',
      type: SyncOpType.upsert,
      bookmark: _bookmark('remote-keep'),
      occurredAt: now,
      deviceId: 'remote-device',
    );
    final SyncBatch batchA = SyncBatch(
      deviceId: 'remote-device',
      createdAt: now,
      ops: <SyncOp>[
        SyncOp(
          opId: 'self-op',
          type: SyncOpType.upsert,
          bookmark: _bookmark('self-should-ignore'),
          occurredAt: now,
          deviceId: 'd1',
        ),
        remoteUpsert,
      ],
    );
    final SyncBatch batchB = SyncBatch(
      deviceId: 'remote-device',
      createdAt: now.add(const Duration(seconds: 1)),
      ops: <SyncOp>[remoteUpsert],
    );

    final _FakeSyncProvider provider = _FakeSyncProvider(
      pulled: <PulledSyncBatch>[
        PulledSyncBatch(batch: batchA, cursorAt: DateTime.utc(2026, 2, 16, 13)),
        PulledSyncBatch(batch: batchB, cursorAt: DateTime.utc(2026, 2, 16, 14)),
      ],
    );

    final SyncEngine engine = SyncEngine(
      localStore: local,
      syncProvider: provider,
      userId: 'u1',
      deviceId: 'd1',
    );

    await engine.syncOnce();

    expect(local.upserted.length, 1);
    expect(local.upserted.single.id, 'remote-keep');
    expect(local.savedCursor, DateTime.utc(2026, 2, 16, 14));
  });
}

class _FakeLocalStore implements LocalStore {
  _FakeLocalStore({
    required List<SyncOp> pendingOps,
    required DateTime lastPulled,
  })  : _pendingOps = pendingOps,
        _lastPulled = lastPulled;

  final List<SyncOp> _pendingOps;
  final DateTime _lastPulled;
  final List<Bookmark> upserted = <Bookmark>[];
  final List<String> deletedIds = <String>[];
  final List<String> markedOpIds = <String>[];
  DateTime? savedCursor;

  @override
  Future<DateTime> lastPulledAt() async => _lastPulled;

  @override
  Future<List<SyncOp>> loadPendingOps() async => _pendingOps;

  @override
  Future<void> markOpsAsPushed(List<String> opIds) async {
    markedOpIds.addAll(opIds);
  }

  @override
  Future<void> saveLastPulledAt(DateTime timestamp) async {
    savedCursor = timestamp;
  }

  @override
  Future<void> upsertBookmark(Bookmark bookmark) async {
    upserted.add(bookmark);
  }

  @override
  Future<void> deleteBookmark(String bookmarkId) async {
    deletedIds.add(bookmarkId);
  }
}

class _FakeSyncProvider implements SyncProvider {
  _FakeSyncProvider({required this.pulled});

  final List<PulledSyncBatch> pulled;
  final List<SyncOp> pushedOps = <SyncOp>[];

  @override
  Future<List<PulledSyncBatch>> pullOpsSince({
    required String userId,
    required DateTime since,
  }) async {
    return pulled;
  }

  @override
  Future<void> pushOps({
    required String userId,
    required String deviceId,
    required List<SyncOp> ops,
  }) async {
    pushedOps.addAll(ops);
  }
}

Bookmark _bookmark(String id) {
  final DateTime now = DateTime.utc(2026, 2, 16, 10, 0, 0);
  return Bookmark(
    id: id,
    url: 'https://example.com/$id',
    normalizedUrl: 'https://example.com/$id',
    createdAt: now,
    updatedAt: now,
  );
}
