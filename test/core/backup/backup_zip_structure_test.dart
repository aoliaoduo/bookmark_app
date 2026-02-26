import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:code/core/backup/cloud_backup_service.dart';
import 'package:code/core/clock/app_clock.dart';
import 'package:code/core/db/app_database.dart';
import 'package:code/core/identity/device_identity_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FixedClock implements AppClock {
  const _FixedClock(this.value);

  final int value;

  @override
  int nowMs() => value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('backup zip contains db.sqlite and manifest.json', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'backup_zip_test_',
    );
    final String dbPath = p.join(tempDir.path, 'app.db');
    final AppDatabase db = await AppDatabase.open(databasePath: dbPath);
    final CloudBackupService service = CloudBackupService(
      database: db,
      clock: const _FixedClock(1730000000000),
      identityService: DeviceIdentityService(),
    );

    final List<int> zipBytes = await service.buildBackupZipBytesForTesting();
    final Archive archive = ZipDecoder().decodeBytes(zipBytes);
    final List<String> names = archive.files
        .map((ArchiveFile f) => f.name)
        .toList();

    expect(names, contains('db.sqlite'));
    expect(names, contains('manifest.json'));

    final ArchiveFile manifestFile = archive.files.firstWhere(
      (ArchiveFile f) => f.name == 'manifest.json',
    );
    final String manifestRaw = utf8.decode((manifestFile.content as List<int>));
    final Object? decoded = jsonDecode(manifestRaw);
    expect(decoded, isA<Map<String, Object?>>());

    await db.close();
    await tempDir.delete(recursive: true);
  });
}
