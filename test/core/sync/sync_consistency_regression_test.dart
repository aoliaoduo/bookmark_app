import 'package:bookmark_app/core/domain/bookmark.dart';
import 'package:bookmark_app/core/sync/sync_engine.dart';
import 'package:bookmark_app/core/sync/sync_provider.dart';
import 'package:bookmark_app/core/sync/sync_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'latest remote delete wins for same bookmark even if pulled later op is old upsert',
      () async {
    final DateTime base = DateTime.utc(2026, 2, 17, 8, 0, 0);
    final String id = 'article-1';
    final SyncOp newerDelete = SyncOp(
      opId: 'delete-new',
      type: SyncOpType.delete,
      bookmark: _bookmark(
        id: id,
        updatedAt: base.add(const Duration(minutes: 10)),
      ).copyWith(
        deletedAt: base.add(const Duration(minutes: 10)),
        updatedAt: base.add(const Duration(minutes: 10)),
      ),
      occurredAt: base.add(const Duration(minutes: 10)),
      deviceId: 'remote-a',
    );
    final SyncOp olderUpsert = SyncOp(
      opId: 'upsert-old',
      type: SyncOpType.upsert,
      bookmark: _bookmark(
        id: id,
        updatedAt: base.add(const Duration(minutes: 5)),
      ),
      occurredAt: base.add(const Duration(minutes: 5)),
      deviceId: 'remote-a',
    );

    final _MemoryLocalStore store = _MemoryLocalStore(
      lastPulled: base,
      pendingOps: const <SyncOp>[],
    );
    final SyncEngine engine = SyncEngine(
      localStore: store,
      syncProvider: _StaticSyncProvider(
        pulled: <PulledSyncBatch>[
          PulledSyncBatch(
            batch: SyncBatch(
              deviceId: 'remote-a',
              createdAt: base.add(const Duration(minutes: 11)),
              ops: <SyncOp>[newerDelete],
            ),
            cursorAt: base.add(const Duration(minutes: 12)),
          ),
          PulledSyncBatch(
            batch: SyncBatch(
              deviceId: 'remote-a',
              createdAt: base.add(const Duration(minutes: 13)),
              ops: <SyncOp>[olderUpsert],
            ),
            cursorAt: base.add(const Duration(minutes: 13)),
          ),
        ],
      ),
      userId: 'user-a',
      deviceId: 'device-local',
    );

    await engine.syncOnce();

    expect(store.deletedBookmarkIds, <String>[id]);
    expect(store.upsertedBookmarks.where((Bookmark b) => b.id == id), isEmpty);
    expect(await store.findBookmarkById(id), isNull);
  });

  test('stale remote delete does not remove local newer bookmark', () async {
    final DateTime base = DateTime.utc(2026, 2, 17, 9, 0, 0);
    final String id = 'article-2';
    final Bookmark localNewer = _bookmark(
      id: id,
      updatedAt: base.add(const Duration(minutes: 20)),
    );
    final SyncOp remoteOlderDelete = SyncOp(
      opId: 'delete-old',
      type: SyncOpType.delete,
      bookmark: _bookmark(
        id: id,
        updatedAt: base.add(const Duration(minutes: 10)),
      ).copyWith(
        deletedAt: base.add(const Duration(minutes: 10)),
        updatedAt: base.add(const Duration(minutes: 10)),
      ),
      occurredAt: base.add(const Duration(minutes: 10)),
      deviceId: 'remote-a',
    );

    final _MemoryLocalStore store = _MemoryLocalStore(
      lastPulled: base,
      pendingOps: const <SyncOp>[],
      initialBookmarks: <Bookmark>[localNewer],
    );
    final SyncEngine engine = SyncEngine(
      localStore: store,
      syncProvider: _StaticSyncProvider(
        pulled: <PulledSyncBatch>[
          PulledSyncBatch(
            batch: SyncBatch(
              deviceId: 'remote-a',
              createdAt: base.add(const Duration(minutes: 11)),
              ops: <SyncOp>[remoteOlderDelete],
            ),
            cursorAt: base.add(const Duration(minutes: 12)),
          ),
        ],
      ),
      userId: 'user-a',
      deviceId: 'device-local',
    );

    await engine.syncOnce();

    expect(store.deletedBookmarkIds, isEmpty);
    final Bookmark? remained = await store.findBookmarkById(id);
    expect(remained, isNotNull);
    expect(remained!.isDeleted, isFalse);
    expect(remained.updatedAt, localNewer.updatedAt);
  });

  test('newer remote delete removes local older bookmark', () async {
    final DateTime base = DateTime.utc(2026, 2, 17, 10, 0, 0);
    final String id = 'article-3';
    final Bookmark localOlder = _bookmark(
      id: id,
      updatedAt: base.add(const Duration(minutes: 5)),
    );
    final SyncOp remoteNewDelete = SyncOp(
      opId: 'delete-new',
      type: SyncOpType.delete,
      bookmark: _bookmark(
        id: id,
        updatedAt: base.add(const Duration(minutes: 15)),
      ).copyWith(
        deletedAt: base.add(const Duration(minutes: 15)),
        updatedAt: base.add(const Duration(minutes: 15)),
      ),
      occurredAt: base.add(const Duration(minutes: 15)),
      deviceId: 'remote-a',
    );

    final _MemoryLocalStore store = _MemoryLocalStore(
      lastPulled: base,
      pendingOps: const <SyncOp>[],
      initialBookmarks: <Bookmark>[localOlder],
    );
    final SyncEngine engine = SyncEngine(
      localStore: store,
      syncProvider: _StaticSyncProvider(
        pulled: <PulledSyncBatch>[
          PulledSyncBatch(
            batch: SyncBatch(
              deviceId: 'remote-a',
              createdAt: base.add(const Duration(minutes: 16)),
              ops: <SyncOp>[remoteNewDelete],
            ),
            cursorAt: base.add(const Duration(minutes: 17)),
          ),
        ],
      ),
      userId: 'user-a',
      deviceId: 'device-local',
    );

    await engine.syncOnce();

    expect(store.deletedBookmarkIds, <String>[id]);
    expect(await store.findBookmarkById(id), isNull);
  });

  test('newer remote upsert can restore local deleted bookmark', () async {
    final DateTime base = DateTime.utc(2026, 2, 17, 11, 0, 0);
    final String id = 'article-4';
    final Bookmark localDeleted = _bookmark(
      id: id,
      updatedAt: base.add(const Duration(minutes: 10)),
    ).copyWith(
      deletedAt: base.add(const Duration(minutes: 10)),
      updatedAt: base.add(const Duration(minutes: 10)),
    );
    final SyncOp remoteRestore = SyncOp(
      opId: 'restore-new',
      type: SyncOpType.upsert,
      bookmark: _bookmark(
        id: id,
        updatedAt: base.add(const Duration(minutes: 20)),
      ),
      occurredAt: base.add(const Duration(minutes: 20)),
      deviceId: 'remote-a',
    );

    final _MemoryLocalStore store = _MemoryLocalStore(
      lastPulled: base,
      pendingOps: const <SyncOp>[],
      initialBookmarks: <Bookmark>[localDeleted],
    );
    final SyncEngine engine = SyncEngine(
      localStore: store,
      syncProvider: _StaticSyncProvider(
        pulled: <PulledSyncBatch>[
          PulledSyncBatch(
            batch: SyncBatch(
              deviceId: 'remote-a',
              createdAt: base.add(const Duration(minutes: 21)),
              ops: <SyncOp>[remoteRestore],
            ),
            cursorAt: base.add(const Duration(minutes: 22)),
          ),
        ],
      ),
      userId: 'user-a',
      deviceId: 'device-local',
    );

    await engine.syncOnce();

    final Bookmark? restored = await store.findBookmarkById(id);
    expect(restored, isNotNull);
    expect(restored!.isDeleted, isFalse);
    expect(restored.updatedAt, remoteRestore.bookmark.updatedAt);
  });

  test('same timestamp tie prefers delete over active local bookmark',
      () async {
    final DateTime at = DateTime.utc(2026, 2, 17, 12, 0, 0);
    final String id = 'article-5';
    final Bookmark local = _bookmark(id: id, updatedAt: at);
    final SyncOp remoteDeleteAtSameTime = SyncOp(
      opId: 'delete-tie',
      type: SyncOpType.delete,
      bookmark: _bookmark(id: id, updatedAt: at).copyWith(
        deletedAt: at,
        updatedAt: at,
      ),
      occurredAt: at,
      deviceId: 'remote-a',
    );

    final _MemoryLocalStore store = _MemoryLocalStore(
      lastPulled: at.subtract(const Duration(minutes: 1)),
      pendingOps: const <SyncOp>[],
      initialBookmarks: <Bookmark>[local],
    );
    final SyncEngine engine = SyncEngine(
      localStore: store,
      syncProvider: _StaticSyncProvider(
        pulled: <PulledSyncBatch>[
          PulledSyncBatch(
            batch: SyncBatch(
              deviceId: 'remote-a',
              createdAt: at,
              ops: <SyncOp>[remoteDeleteAtSameTime],
            ),
            cursorAt: at,
          ),
        ],
      ),
      userId: 'user-a',
      deviceId: 'device-local',
    );

    await engine.syncOnce();

    expect(store.deletedBookmarkIds, <String>[id]);
    expect(await store.findBookmarkById(id), isNull);
  });
}

class _MemoryLocalStore implements LocalStore {
  _MemoryLocalStore({
    required DateTime lastPulled,
    required List<SyncOp> pendingOps,
    List<Bookmark> initialBookmarks = const <Bookmark>[],
  })  : _lastPulled = lastPulled,
        _pendingOps = pendingOps {
    for (final Bookmark bookmark in initialBookmarks) {
      _bookmarks[bookmark.id] = bookmark;
    }
  }

  final DateTime _lastPulled;
  final List<SyncOp> _pendingOps;
  final Map<String, Bookmark> _bookmarks = <String, Bookmark>{};

  final List<String> markedOpIds = <String>[];
  final List<String> deletedBookmarkIds = <String>[];
  final List<Bookmark> upsertedBookmarks = <Bookmark>[];
  DateTime? savedLastPulled;

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
    savedLastPulled = timestamp;
  }

  @override
  Future<Bookmark?> findBookmarkById(String bookmarkId) async {
    return _bookmarks[bookmarkId];
  }

  @override
  Future<void> upsertBookmark(Bookmark bookmark) async {
    upsertedBookmarks.add(bookmark);
    _bookmarks[bookmark.id] = bookmark;
  }

  @override
  Future<void> deleteBookmark(String bookmarkId) async {
    deletedBookmarkIds.add(bookmarkId);
    _bookmarks.remove(bookmarkId);
  }
}

class _StaticSyncProvider implements SyncProvider {
  _StaticSyncProvider({required this.pulled});

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

Bookmark _bookmark({
  required String id,
  required DateTime updatedAt,
}) {
  final DateTime createdAt = updatedAt.subtract(const Duration(minutes: 1));
  return Bookmark(
    id: id,
    url: 'https://example.com/$id',
    normalizedUrl: 'https://example.com/$id',
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
