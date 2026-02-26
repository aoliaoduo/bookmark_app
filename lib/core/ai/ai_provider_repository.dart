import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../clock/app_clock.dart';
import '../clock/lamport_clock.dart';
import '../db/app_database.dart';
import '../identity/device_identity_service.dart';
import '../sync/change_log_repository.dart';
import '../sync/sync_models.dart';
import 'ai_provider_config.dart';

class AiProviderRepository {
  AiProviderRepository({
    required this.database,
    required this.identityService,
    required this.lamportClock,
    required this.clock,
    required this.changeLogRepository,
  });

  static const String _kvKey = 'ai_provider_json';
  static const String _lastErrorKey = 'ai_last_error';

  final AppDatabase database;
  final DeviceIdentityService identityService;
  final LamportClock lamportClock;
  final AppClock clock;
  final ChangeLogRepository changeLogRepository;

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
      final String deviceId = await identityService.getOrCreateDeviceId(txn);
      final int lamport = await lamportClock.next(txn);
      final int now = clock.nowMs();
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
      await changeLogRepository.append(
        executor: txn,
        entityType: 'secret',
        entityId: 'api_provider',
        operation: SyncOperation.upsert,
        lamport: lamport,
        deviceId: deviceId,
        createdAt: now,
      );
    });
  }

  Future<void> clear() async {
    await database.db.transaction((txn) async {
      final String deviceId = await identityService.getOrCreateDeviceId(txn);
      final int lamport = await lamportClock.next(txn);
      final int now = clock.nowMs();
      await txn.delete(
        'kv',
        where: 'key = ?',
        whereArgs: const <Object?>[_kvKey],
      );
      await changeLogRepository.append(
        executor: txn,
        entityType: 'secret',
        entityId: 'api_provider',
        operation: SyncOperation.delete,
        lamport: lamport,
        deviceId: deviceId,
        createdAt: now,
      );
    });
  }

  Future<void> saveLastError(String message) async {
    await database.db.insert('kv', <String, Object?>{
      'key': _lastErrorKey,
      'value': message,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearLastError() async {
    await database.db.delete(
      'kv',
      where: 'key = ?',
      whereArgs: const <Object?>[_lastErrorKey],
    );
  }
}
