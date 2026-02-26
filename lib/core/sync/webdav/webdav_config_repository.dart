import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../db/app_database.dart';
import 'webdav_config.dart';

class WebDavConfigRepository {
  WebDavConfigRepository(this.database);

  static const String _kvKey = 'webdav_config_json';
  final AppDatabase database;

  Future<WebDavConfig> load() async {
    final List<Map<String, Object?>> rows = await database.db.query(
      'kv',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: const <Object?>[_kvKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return WebDavConfig.empty;
    }
    final String raw = (rows.first['value'] as String?) ?? '{}';
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      return WebDavConfig.empty;
    }
    return WebDavConfig.fromJson(decoded);
  }

  Future<void> save(WebDavConfig config) async {
    final String payload = jsonEncode(config.toJson());
    await database.db.insert('kv', <String, Object?>{
      'key': _kvKey,
      'value': payload,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
