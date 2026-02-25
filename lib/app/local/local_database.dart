import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../platform/platform_adapter.dart';
import '../../platform/platform_services.dart';

class LocalDatabase {
  LocalDatabase._({PlatformAdapter? platformAdapter})
      : _platform = platformAdapter ?? PlatformServices.instance.platform;

  static final LocalDatabase instance = LocalDatabase._();
  Database? _database;
  Future<Database>? _openingDatabase;
  final PlatformAdapter _platform;

  Future<Database> get database async {
    final Database? opened = _database;
    if (opened != null) {
      return opened;
    }

    final Future<Database>? opening = _openingDatabase;
    if (opening != null) {
      return opening;
    }

    final Future<Database> openFuture = _open();
    _openingDatabase = openFuture;
    try {
      final Database db = await openFuture;
      _database = db;
      return db;
    } finally {
      if (identical(_openingDatabase, openFuture)) {
        _openingDatabase = null;
      }
    }
  }

  Future<Database> _open() async {
    final PlatformCapabilities caps = _platform.capabilities;
    if (!caps.isWeb && caps.isDesktop) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final Directory appDir = Directory(
      await _platform.getApplicationSupportPath(),
    );
    await appDir.create(recursive: true);
    final String dbPath = path.join(appDir.path, 'bookmark_app.db');

    return openDatabase(
      dbPath,
      version: 3,
      onConfigure: (Database db) async {
        await _configurePragmas(db);
      },
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
  bookmark_id TEXT,
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

        await db.execute(
          'CREATE INDEX idx_outbox_pushed ON sync_outbox(pushed, occurred_at)',
        );
        await db.execute(
          'CREATE INDEX idx_outbox_bookmark_pending ON sync_outbox(bookmark_id, pushed, occurred_at)',
        );
        await db.execute(
          'CREATE INDEX idx_bookmarks_updated ON bookmarks(updated_at)',
        );
        await db.execute(
          'CREATE INDEX idx_tombstones_expire ON sync_tombstones(expire_at)',
        );
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
CREATE TABLE IF NOT EXISTS sync_tombstones(
  bookmark_id TEXT PRIMARY KEY,
  deleted_at TEXT NOT NULL,
  expire_at TEXT NOT NULL
)
''');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_tombstones_expire ON sync_tombstones(expire_at)',
          );
        }
        if (oldVersion < 3) {
          await _tryExecute(
            db,
            'ALTER TABLE sync_outbox ADD COLUMN bookmark_id TEXT',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_outbox_bookmark_pending ON sync_outbox(bookmark_id, pushed, occurred_at)',
          );
        }
      },
    );
  }

  Future<void> _configurePragmas(Database db) async {
    // 优先保证数据落盘稳定性：启用 WAL + FULL 同步 + 连接忙等待。
    await _tryRawQuery(db, 'PRAGMA journal_mode = WAL');
    await _tryExecute(db, 'PRAGMA synchronous = FULL');
    await _tryExecute(db, 'PRAGMA wal_autocheckpoint = 1000');
    await _tryExecute(db, 'PRAGMA foreign_keys = ON');
    await _tryExecute(db, 'PRAGMA busy_timeout = 5000');
  }

  Future<void> _tryExecute(Database db, String sql) async {
    try {
      await db.execute(sql);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Ignored SQLite execute error: $sql; $e');
      }
    }
  }

  Future<void> _tryRawQuery(Database db, String sql) async {
    try {
      await db.rawQuery(sql);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Ignored SQLite query error: $sql; $e');
      }
    }
  }
}
