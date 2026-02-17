import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LocalDatabase {
  LocalDatabase._();

  static final LocalDatabase instance = LocalDatabase._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _open();
    return _database!;
  }

  Future<Database> _open() async {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final Directory appDir = await getApplicationSupportDirectory();
    await appDir.create(recursive: true);
    final String dbPath = path.join(appDir.path, 'bookmark_app.db');

    return openDatabase(
      dbPath,
      version: 1,
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

        await db.execute(
          'CREATE INDEX idx_outbox_pushed ON sync_outbox(pushed, occurred_at)',
        );
        await db.execute(
          'CREATE INDEX idx_bookmarks_updated ON bookmarks(updated_at)',
        );
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
    } catch (_) {}
  }

  Future<void> _tryRawQuery(Database db, String sql) async {
    try {
      await db.rawQuery(sql);
    } catch (_) {}
  }
}
