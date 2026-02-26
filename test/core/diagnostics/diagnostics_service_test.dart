import 'dart:convert';
import 'dart:io';

import 'package:code/core/ai/ai_provider_repository.dart';
import 'package:code/core/backup/backup_settings_repository.dart';
import 'package:code/core/clock/app_clock.dart';
import 'package:code/core/clock/lamport_clock.dart';
import 'package:code/core/db/app_database.dart';
import 'package:code/core/diagnostics/diagnostics_service.dart';
import 'package:code/core/identity/device_identity_service.dart';
import 'package:code/core/sync/change_log_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class _FixedClock implements AppClock {
  const _FixedClock(this.value);

  final int value;

  @override
  int nowMs() => value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('diagnostics export payload redacts api key by default', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'diagnostics_test_',
    );
    final String dbPath = p.join(tempDir.path, 'diagnostics.db');
    final AppDatabase db = await AppDatabase.open(databasePath: dbPath);

    await db.db.insert('kv', <String, Object?>{
      'key': 'ai_provider_json',
      'value': jsonEncode(<String, Object?>{
        'base_url': 'https://example.com',
        'api_root': 'https://example.com/v1',
        'api_key': 'secret-key-123',
        'selected_model': 'gpt-test',
        'risk_confirmed': true,
      }),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    final DiagnosticsService service = DiagnosticsService(
      database: db,
      aiProviderRepository: AiProviderRepository(
        database: db,
        identityService: DeviceIdentityService(),
        lamportClock: LamportClock(),
        clock: const _FixedClock(1730000000000),
        changeLogRepository: ChangeLogRepository(db.db),
      ),
      backupSettingsRepository: BackupSettingsRepository(db),
      clock: const _FixedClock(1730000000000),
    );

    final Map<String, Object?> payload = await service.buildPayload();
    final String encoded = jsonEncode(payload);
    expect(encoded, isNot(contains('secret-key-123')));
    expect(encoded, contains('<redacted>'));

    final Map<String, Object?> payloadSensitive = await service.buildPayload(
      includeSensitive: true,
    );
    final String encodedSensitive = jsonEncode(payloadSensitive);
    expect(encodedSensitive, contains('secret-key-123'));

    await db.close();
    await tempDir.delete(recursive: true);
  });
}
