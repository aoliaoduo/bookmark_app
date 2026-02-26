import 'dart:io';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:sqflite/sqflite.dart';

const int kCurrentDbVersion = 1;

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
