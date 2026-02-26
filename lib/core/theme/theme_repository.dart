import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import 'theme_models.dart';
import 'theme_registry.dart';

class ThemeRepository {
  ThemeRepository(this.database);

  static const String _key = 'theme_selection_json';

  final AppDatabase database;

  Future<ThemeSelection> load() async {
    final List<Map<String, Object?>> rows = await database.db.query(
      'kv',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[_key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return ThemeSelection.defaults;
    }

    final String raw = (rows.first['value'] as String?) ?? '';
    if (raw.isEmpty) {
      return ThemeSelection.defaults;
    }

    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return ThemeSelection.defaults;
      }
      final AppThemeMode mode = AppThemeModeX.fromStorage(
        (decoded['mode'] as String?) ?? '',
      );
      final String presetId = (decoded['preset_id'] as String?) ?? 'material';
      final String normalizedPreset = ThemeRegistry.byId(presetId).id;
      return ThemeSelection(mode: mode, presetId: normalizedPreset);
    } catch (_) {
      return ThemeSelection.defaults;
    }
  }

  Future<void> save(ThemeSelection selection) async {
    final ThemeSelection normalized = selection.copyWith(
      presetId: ThemeRegistry.byId(selection.presetId).id,
    );
    await database.db.insert('kv', <String, Object?>{
      'key': _key,
      'value': jsonEncode(<String, Object?>{
        'mode': normalized.mode.storageValue,
        'preset_id': normalized.presetId,
      }),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
