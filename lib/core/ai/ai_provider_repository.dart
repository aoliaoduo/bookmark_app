import 'dart:convert';

import '../db/app_database.dart';
import 'ai_provider_config.dart';

class AiProviderRepository {
  AiProviderRepository(this.database);

  static const String _kvKey = 'ai_provider_json';

  final AppDatabase database;

  Future<AiProviderConfig> load() async {
    final List<Map<String, Object?>> rows = await database.db.query(
      'kv',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: const <Object?>[_kvKey],
      limit: 1,
    );

    if (rows.isEmpty) {
      return AiProviderConfig.empty;
    }

    final String raw = (rows.first['value'] as String?) ?? '{}';
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      return AiProviderConfig.empty;
    }
    return AiProviderConfig.fromJson(decoded);
  }

  Future<void> save(AiProviderConfig config) async {
    final String payload = jsonEncode(config.toJson());
    await database.db.transaction((txn) async {
      final List<Map<String, Object?>> rows = await txn.query(
        'kv',
        columns: ['key'],
        where: 'key = ?',
        whereArgs: const <Object?>[_kvKey],
        limit: 1,
      );

      if (rows.isEmpty) {
        await txn.insert('kv', {'key': _kvKey, 'value': payload});
      } else {
        await txn.update(
          'kv',
          {'value': payload},
          where: 'key = ?',
          whereArgs: const <Object?>[_kvKey],
        );
      }
    });
  }

  Future<void> clear() async {
    await database.db.delete(
      'kv',
      where: 'key = ?',
      whereArgs: const <Object?>[_kvKey],
    );
  }
}
