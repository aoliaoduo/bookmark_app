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

    final SyncEngineReport report = await engine.syncOnce();

    expect(local.savedCursor, serverCursor);
    expect(local.markedOpIds, isEmpty);
    expect(local.upserted.length, 1);
    expect(local.upserted.single.id, 'b-1');
    expect(local.deletedIds, isEmpty);
    expect(report.localPendingOps, 0);
    expect(report.pushedOps, 0);
    expect(report.pulledBatchCount, 1);
    expect(report.pulledOps, 1);
    expect(report.filteredSelfDeviceOps, 0);
    expect(report.filteredDuplicateOps, 0);
    expect(report.appliedUpserts, 1);
    expect(report.appliedDeletes, 0);
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

    final SyncEngineReport report = await engine.syncOnce();

    expect(provider.pushedOps.length, 2);
    expect(
      provider.pushedOps.map((SyncOp op) => op.opId).toSet(),
      <String>{'op-local-delete', 'op-local-upsert'},
    );
    expect(local.markedOpIds, <String>['op-local-delete', 'op-local-upsert']);
    expect(local.upserted.length, 1);
    expect(local.upserted.single.id, 'remote-keep');
    expect(local.deletedIds, <String>['remote-trash']);
    expect(report.localPendingOps, 2);
    expect(report.pushedOps, 2);
    expect(report.pulledBatchCount, 1);
    expect(report.pulledOps, 2);
    expect(report.filteredSelfDeviceOps, 0);
    expect(report.filteredDuplicateOps, 0);
    expect(report.appliedUpserts, 1);
    expect(report.appliedDeletes, 1);
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

    final SyncEngineReport report = await engine.syncOnce();

    expect(local.upserted.length, 1);
    expect(local.upserted.single.id, 'remote-keep');
    expect(local.savedCursor, DateTime.utc(2026, 2, 16, 14));
    expect(report.pulledOps, 3);
    expect(report.filteredSelfDeviceOps, 1);
    expect(report.filteredDuplicateOps, 1);
    expect(report.appliedUpserts, 1);
  });

  test('syncOnce passes cursor paths to provider and persists new max paths',
      () async {
    final DateTime since = DateTime.utc(2026, 2, 16, 14, 0, 0);
    final _FakeLocalStore local = _FakeLocalStore(
      pendingOps: const <SyncOp>[],
      lastPulled: since,
      lastPulledPathsAtCursor: <String>['/ops/already-seen.json'],
    );
    final _FakeSyncProvider provider = _FakeSyncProvider(
      pulled: <PulledSyncBatch>[
        PulledSyncBatch(
          batch: SyncBatch(
            deviceId: 'remote-device',
            createdAt: since,
            ops: <SyncOp>[
              SyncOp(
                opId: 'op-a',
                type: SyncOpType.upsert,
                bookmark: _bookmark('b-a'),
                occurredAt: since,
                deviceId: 'remote-device',
              ),
            ],
          ),
          cursorAt: since.add(const Duration(minutes: 1)),
          sourcePath: '/ops/new-a.json',
        ),
        PulledSyncBatch(
          batch: SyncBatch(
            deviceId: 'remote-device',
            createdAt: since,
            ops: <SyncOp>[
              SyncOp(
                opId: 'op-b',
                type: SyncOpType.upsert,
                bookmark: _bookmark('b-b'),
                occurredAt: since,
                deviceId: 'remote-device',
              ),
            ],
          ),
          cursorAt: since.add(const Duration(minutes: 1)),
          sourcePath: '/ops/new-b.json',
        ),
      ],
    );

    final SyncEngine engine = SyncEngine(
      localStore: local,
      syncProvider: provider,
      userId: 'u1',
      deviceId: 'd1',
    );

    await engine.syncOnce();

    expect(provider.lastPathsAtCursor, <String>{'/ops/already-seen.json'});
    expect(local.savedCursor, since.add(const Duration(minutes: 1)));
    expect(
        local.savedCursorPaths, <String>['/ops/new-a.json', '/ops/new-b.json']);
  });
}

class _FakeLocalStore implements LocalStore {
  _FakeLocalStore({
    required List<SyncOp> pendingOps,
    required DateTime lastPulled,
    List<String> lastPulledPathsAtCursor = const <String>[],
    List<Bookmark> initialBookmarks = const <Bookmark>[],
  })  : _pendingOps = pendingOps,
        _lastPulled = lastPulled,
        _lastPulledPathsAtCursor = lastPulledPathsAtCursor {
    for (final Bookmark bookmark in initialBookmarks) {
      _records[bookmark.id] = bookmark;
    }
  }

  final List<SyncOp> _pendingOps;
  final DateTime _lastPulled;
  final List<String> _lastPulledPathsAtCursor;
  final List<Bookmark> upserted = <Bookmark>[];
  final List<String> deletedIds = <String>[];
  final List<String> markedOpIds = <String>[];
  final Map<String, Bookmark> _records = <String, Bookmark>{};
  final Map<String, DateTime> _tombstones = <String, DateTime>{};
  DateTime? savedCursor;
  List<String> savedCursorPaths = const <String>[];

  @override
  Future<DateTime> lastPulledAt() async => _lastPulled;

  @override
  Future<List<SyncOp>> loadPendingOps() async => _pendingOps;

  @override
  Future<List<String>> lastPulledPathsAtCursor() async {
    return _lastPulledPathsAtCursor;
  }

  @override
  Future<Bookmark?> findBookmarkById(String bookmarkId) async {
    return _records[bookmarkId];
  }

  @override
  Future<DateTime?> findTombstoneAt(String bookmarkId) async {
    return _tombstones[bookmarkId];
  }

  @override
  Future<void> markOpsAsPushed(List<String> opIds) async {
    markedOpIds.addAll(opIds);
  }

  @override
  Future<void> saveLastPulledAt(DateTime timestamp) async {
    savedCursor = timestamp;
  }

  @override
  Future<void> saveLastPulledCursor({
    required DateTime timestamp,
    required List<String> pathsAtTimestamp,
  }) async {
    savedCursor = timestamp;
    savedCursorPaths = pathsAtTimestamp;
  }

  @override
  Future<void> saveTombstone(String bookmarkId, DateTime deletedAt) async {
    _tombstones[bookmarkId] = deletedAt;
  }

  @override
  Future<void> clearTombstone(String bookmarkId) async {
    _tombstones.remove(bookmarkId);
  }

  @override
  Future<void> upsertBookmark(Bookmark bookmark) async {
    upserted.add(bookmark);
    _records[bookmark.id] = bookmark;
  }

  @override
  Future<void> deleteBookmark(String bookmarkId) async {
    deletedIds.add(bookmarkId);
    _records.remove(bookmarkId);
  }
}

class _FakeSyncProvider implements SyncProvider {
  _FakeSyncProvider({required this.pulled});

  final List<PulledSyncBatch> pulled;
  final List<SyncOp> pushedOps = <SyncOp>[];
  Set<String> lastPathsAtCursor = const <String>{};

  @override
  Future<List<PulledSyncBatch>> pullOpsSince({
    required String userId,
    required DateTime since,
    Set<String> pathsAtCursor = const <String>{},
  }) async {
    lastPathsAtCursor = pathsAtCursor;
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
