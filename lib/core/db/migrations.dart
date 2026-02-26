import 'dart:io';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:sqflite/sqflite.dart';

const int kCurrentDbVersion = 2;

final Logger _migrationLog = Logger('DbMigrations');

Future<void> onCreate(Database db, int version) async {
  _migrationLog.info('数据库创建，版本=$version');
  final String schemaSql = await _loadSchemaSql();
  await _executeSqlScript(db, schemaSql);
}

Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
  _migrationLog.info('数据库迁移：$oldVersion -> $newVersion');
  if (oldVersion < 1 && newVersion >= 1) {
    final String schemaSql = await _loadSchemaSql();
    await _executeSqlScript(db, schemaSql);
  }
  if (oldVersion < 2 && newVersion >= 2) {
    await _migrateToV2(db);
  }
}

Future<String> _loadSchemaSql() async {
  const String assetPath = 'lib/core/db/schema_v1.sql';
  try {
    return await rootBundle.loadString(assetPath);
  } catch (_) {
    return File(assetPath).readAsString();
  }
}

Future<void> _executeSqlScript(Database db, String sqlScript) async {
  final List<String> statements = _splitSqlStatements(sqlScript);
  final Batch batch = db.batch();
  for (final String statement in statements) {
    batch.execute(statement);
  }
  await batch.commit(noResult: true);
}

List<String> _splitSqlStatements(String sqlScript) {
  final String noComments = sqlScript
      .split('\n')
      .where((String line) => !line.trimLeft().startsWith('--'))
      .join('\n');

  return noComments
      .split(';')
      .map((String statement) => statement.trim())
      .where((String statement) => statement.isNotEmpty)
      .toList(growable: false);
}

Future<void> _migrateToV2(Database db) async {
  const List<String> statements = <String>[
    '''
    CREATE TABLE IF NOT EXISTS change_log (
      id TEXT PRIMARY KEY,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      operation TEXT NOT NULL,
      lamport INTEGER NOT NULL,
      device_id TEXT NOT NULL,
      payload_json TEXT,
      created_at INTEGER NOT NULL,
      synced_at INTEGER,
      retry_count INTEGER NOT NULL DEFAULT 0,
      last_error TEXT
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS processed_changes (
      change_id TEXT PRIMARY KEY,
      source_device_id TEXT NOT NULL,
      applied_at INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS sync_state (
      id TEXT PRIMARY KEY,
      last_sync_started_at INTEGER,
      last_sync_finished_at INTEGER,
      next_allowed_sync_at INTEGER,
      backoff_until INTEGER,
      last_error TEXT,
      last_applied_change_id TEXT,
      last_pushed_change_id TEXT,
      request_window_started_at INTEGER,
      request_count_in_window INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL
    )
    ''',
  ];
  final Batch batch = db.batch();
  for (final String statement in statements) {
    batch.execute(statement);
  }
  await batch.commit(noResult: true);
}
