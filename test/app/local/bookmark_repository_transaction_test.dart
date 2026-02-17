import 'package:bookmark_app/app/local/bookmark_repository.dart';
import 'package:bookmark_app/core/metadata/metadata_fetch_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('addUrl rolls back bookmark insert when outbox insert fails', () async {
    final Database db = await _openDb();
    addTearDown(() async {
      await db.close();
    });
    final BookmarkRepository repository = BookmarkRepository(
      db: db,
      metadataService: MetadataFetchService(),
      deviceId: 'device-1',
    );

    await db.execute('''
CREATE TRIGGER trg_fail_outbox_insert
BEFORE INSERT ON sync_outbox
BEGIN
  SELECT RAISE(ABORT, 'outbox_fail');
END;
''');

    expect(
      () => repository.addUrl('https://example.com'),
      throwsA(isA<DatabaseException>()),
    );

    final List<Map<String, Object?>> bookmarkRows = await db.query('bookmarks');
    final List<Map<String, Object?>> outboxRows = await db.query('sync_outbox');
    expect(bookmarkRows, isEmpty);
    expect(outboxRows, isEmpty);
  });

  test('softDelete rolls back deleted state and tombstone when outbox fails',
      () async {
    final Database db = await _openDb();
    addTearDown(() async {
      await db.close();
    });
    final BookmarkRepository repository = BookmarkRepository(
      db: db,
      metadataService: MetadataFetchService(),
      deviceId: 'device-1',
    );
    final DateTime now = DateTime.utc(2026, 2, 17, 0, 0, 0);
    await db.insert('bookmarks', <String, Object?>{
      'id': 'b-1',
      'url': 'https://example.com',
      'normalized_url': 'https://example.com',
      'title': 'Example',
      'note': null,
      'tags_json': '[]',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'deleted_at': null,
      'title_updated_at': null,
    });

    await db.execute('''
CREATE TRIGGER trg_fail_outbox_insert
BEFORE INSERT ON sync_outbox
BEGIN
  SELECT RAISE(ABORT, 'outbox_fail');
END;
''');

    expect(
      () => repository.softDelete('b-1'),
      throwsA(isA<DatabaseException>()),
    );

    final List<Map<String, Object?>> rows = await db.query(
      'bookmarks',
      where: 'id = ?',
      whereArgs: <Object?>['b-1'],
    );
    expect(rows, hasLength(1));
    expect(rows.single['deleted_at'], isNull);

    final List<Map<String, Object?>> tombstones = await db.query(
      'sync_tombstones',
      where: 'bookmark_id = ?',
      whereArgs: <Object?>['b-1'],
    );
    expect(tombstones, isEmpty);
  });
}

Future<Database> _openDb() {
  return openDatabase(
    inMemoryDatabasePath,
    version: 1,
    onCreate: (Database db, int _) async {
      await db.execute('''
CREATE TABLE bookmarks(
  id TEXT PRIMARY KEY,
  url TEXT NOT NULL,
  normalized_url TEXT NOT NULL,
  title TEXT,
  note TEXT,
  tags_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  title_updated_at TEXT
)
''');
      await db.execute('''
CREATE TABLE sync_outbox(
  op_id TEXT PRIMARY KEY,
  op_type TEXT NOT NULL,
  bookmark_json TEXT NOT NULL,
  occurred_at TEXT NOT NULL,
  device_id TEXT NOT NULL,
  pushed INTEGER NOT NULL DEFAULT 0
)
''');
      await db.execute('''
CREATE TABLE sync_state(
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
)
''');
      await db.execute('''
CREATE TABLE sync_tombstones(
  bookmark_id TEXT PRIMARY KEY,
  deleted_at TEXT NOT NULL,
  expire_at TEXT NOT NULL
)
''');
    },
  );
}
