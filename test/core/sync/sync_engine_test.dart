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
    expect(local.upserted.length, 1);
    expect(local.upserted.single.id, 'b-1');
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
  DateTime? savedCursor;

  @override
  Future<DateTime> lastPulledAt() async => _lastPulled;

  @override
  Future<List<SyncOp>> loadPendingOps() async => _pendingOps;

  @override
  Future<void> markOpsAsPushed(List<String> opIds) async {}

  @override
  Future<void> saveLastPulledAt(DateTime timestamp) async {
    savedCursor = timestamp;
  }

  @override
  Future<void> upsertBookmark(Bookmark bookmark) async {
    upserted.add(bookmark);
  }
}

class _FakeSyncProvider implements SyncProvider {
  _FakeSyncProvider({required this.pulled});

  final List<PulledSyncBatch> pulled;

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
  }) async {}
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
