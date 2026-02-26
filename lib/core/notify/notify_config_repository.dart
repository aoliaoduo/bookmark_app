import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import 'notify_config.dart';

class NotifyConfigRepository {
  NotifyConfigRepository(this.database);

  final AppDatabase database;

  static const String _feishuKey = 'notify_feishu_json';
  static const String _smtpKey = 'notify_smtp_json';

  Future<NotifyConfigs> loadAll() async {
    final FeishuNotifyConfig feishu = await loadFeishu();
    final SmtpNotifyConfig smtp = await loadSmtp();
    return NotifyConfigs(feishu: feishu, smtp: smtp);
  }

  Future<FeishuNotifyConfig> loadFeishu() async {
    final String raw = await _loadKv(_feishuKey);
    if (raw.isEmpty) {
      return FeishuNotifyConfig.empty;
    }
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return FeishuNotifyConfig.empty;
    }
    return FeishuNotifyConfig.fromJson(decoded);
  }

  Future<SmtpNotifyConfig> loadSmtp() async {
    final String raw = await _loadKv(_smtpKey);
    if (raw.isEmpty) {
      return SmtpNotifyConfig.empty;
    }
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return SmtpNotifyConfig.empty;
    }
    return SmtpNotifyConfig.fromJson(decoded);
  }

  Future<void> saveFeishu(FeishuNotifyConfig config) async {
    await _saveKv(_feishuKey, jsonEncode(config.toJson()));
  }

  Future<void> saveSmtp(SmtpNotifyConfig config) async {
    await _saveKv(_smtpKey, jsonEncode(config.toJson()));
  }

  Future<String> _loadKv(String key) async {
    final List<Map<String, Object?>> rows = await database.db.query(
      'kv',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return '';
    }
    return (rows.first['value'] as String?) ?? '';
  }

  Future<void> _saveKv(String key, String value) async {
    await database.db.insert('kv', <String, Object?>{
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
