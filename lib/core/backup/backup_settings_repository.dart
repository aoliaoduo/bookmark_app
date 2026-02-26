import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';

class BackupSettings {
  const BackupSettings({
    required this.reminderHour,
    required this.reminderMinute,
    required this.retentionCount,
  });

  static const BackupSettings defaults = BackupSettings(
    reminderHour: 14,
    reminderMinute: 0,
    retentionCount: 30,
  );

  final int reminderHour;
  final int reminderMinute;
  final int retentionCount;

  String get reminderHm =>
      '${reminderHour.toString().padLeft(2, '0')}:${reminderMinute.toString().padLeft(2, '0')}';
}

class BackupSettingsRepository {
  BackupSettingsRepository(this.database);

  final AppDatabase database;

  static const String _keyReminderHm = 'backup_reminder_hm';
  static const String _keyRetention = 'backup_retention_count';
  static const String _keyLastPromptDate = 'backup_last_prompt_date';

  Future<BackupSettings> loadSettings() async {
    final String hm = await _loadKv(
      _keyReminderHm,
      fallback: BackupSettings.defaults.reminderHm,
    );
    final int retention =
        int.tryParse(
          await _loadKv(
            _keyRetention,
            fallback: '${BackupSettings.defaults.retentionCount}',
          ),
        ) ??
        BackupSettings.defaults.retentionCount;
    final List<String> parts = hm.split(':');
    final int hour = parts.isNotEmpty
        ? (int.tryParse(parts.first) ?? BackupSettings.defaults.reminderHour)
        : BackupSettings.defaults.reminderHour;
    final int minute = parts.length > 1
        ? (int.tryParse(parts[1]) ?? BackupSettings.defaults.reminderMinute)
        : BackupSettings.defaults.reminderMinute;
    return BackupSettings(
      reminderHour: hour.clamp(0, 23),
      reminderMinute: minute.clamp(0, 59),
      retentionCount: retention.clamp(1, 365),
    );
  }

  Future<void> saveSettings(BackupSettings settings) async {
    await database.db.transaction((txn) async {
      await txn.insert('kv', <String, Object?>{
        'key': _keyReminderHm,
        'value': settings.reminderHm,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('kv', <String, Object?>{
        'key': _keyRetention,
        'value': '${settings.retentionCount}',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<String?> loadLastPromptDate() async {
    final List<Map<String, Object?>> rows = await database.db.query(
      'kv',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[_keyLastPromptDate],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['value'] as String?;
  }

  Future<void> markPromptedToday(DateTime nowLocal) async {
    final String ymd = _formatDate(nowLocal);
    await database.db.insert('kv', <String, Object?>{
      'key': _keyLastPromptDate,
      'value': ymd,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> shouldPromptNow(DateTime nowLocal) async {
    final BackupSettings settings = await loadSettings();
    final DateTime reminderAt = DateTime(
      nowLocal.year,
      nowLocal.month,
      nowLocal.day,
      settings.reminderHour,
      settings.reminderMinute,
    );
    if (nowLocal.isBefore(reminderAt)) {
      return false;
    }
    final String today = _formatDate(nowLocal);
    final String? lastPrompt = await loadLastPromptDate();
    return lastPrompt != today;
  }

  Future<String> _loadKv(String key, {required String fallback}) async {
    final List<Map<String, Object?>> rows = await database.db.query(
      'kv',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return fallback;
    }
    return (rows.first['value'] as String?) ?? fallback;
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
