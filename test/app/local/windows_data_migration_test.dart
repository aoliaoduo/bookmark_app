import 'dart:io';

import 'package:bookmark_app/app/local/windows_data_migration.dart';
import 'package:bookmark_app/platform/file_dialog_adapter.dart';
import 'package:bookmark_app/platform/platform_adapter.dart';
import 'package:bookmark_app/platform/platform_services.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    PlatformServices.resetToDefault();
  });

  test(
      'migrateLegacyBookmarkAppData skips when current platform is not windows',
      () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'bookmark-migration-not-windows-',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final Directory currentDir = Directory(p.join(root.path, 'current'));
    final Directory legacyDir = Directory(p.join(root.path, 'bookmark_app'));
    await legacyDir.create(recursive: true);
    await File(p.join(legacyDir.path, 'bookmark_app.db')).writeAsString(
      'legacy-db',
    );

    PlatformServices.configureForTest(
      PlatformServices(
        platformAdapter: _FakePlatformAdapter(
          supportPath: currentDir.path,
          capabilities: const PlatformCapabilities(
            isWeb: false,
            isWindows: false,
            isLinux: false,
            isMacOS: false,
            isAndroid: true,
            isIOS: false,
          ),
        ),
        fileDialogAdapter: const _NoopFileDialogAdapter(),
      ),
    );

    await WindowsDataMigration.migrateLegacyBookmarkAppData();

    expect(
        File(p.join(currentDir.path, 'bookmark_app.db')).existsSync(), isFalse);
  });

  test('migrateLegacyBookmarkAppData copies db wal shm on windows', () async {
    final Directory root = await Directory.systemTemp.createTemp(
      'bookmark-migration-windows-',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final Directory currentDir = Directory(p.join(root.path, 'current'));
    final Directory legacyDir = Directory(p.join(root.path, 'bookmark_app'));
    await legacyDir.create(recursive: true);

    final Map<String, String> expected = <String, String>{
      'bookmark_app.db': 'legacy-db',
      'bookmark_app.db-wal': 'legacy-wal',
      'bookmark_app.db-shm': 'legacy-shm',
    };
    for (final MapEntry<String, String> entry in expected.entries) {
      await File(p.join(legacyDir.path, entry.key)).writeAsString(entry.value);
    }

    PlatformServices.configureForTest(
      PlatformServices(
        platformAdapter: _FakePlatformAdapter(
          supportPath: currentDir.path,
          capabilities: const PlatformCapabilities(
            isWeb: false,
            isWindows: true,
            isLinux: false,
            isMacOS: false,
            isAndroid: false,
            isIOS: false,
          ),
        ),
        fileDialogAdapter: const _NoopFileDialogAdapter(),
      ),
    );

    await WindowsDataMigration.migrateLegacyBookmarkAppData();

    for (final MapEntry<String, String> entry in expected.entries) {
      final File copied = File(p.join(currentDir.path, entry.key));
      expect(copied.existsSync(), isTrue);
      expect(await copied.readAsString(), entry.value);
    }
  });
}

class _FakePlatformAdapter implements PlatformAdapter {
  _FakePlatformAdapter({
    required this.supportPath,
    required this.capabilities,
  });

  final String supportPath;

  @override
  final PlatformCapabilities capabilities;

  @override
  Future<String> getApplicationSupportPath() async => supportPath;

  @override
  String? preferredAppFontFamily() => null;
}

class _NoopFileDialogAdapter implements FileDialogAdapter {
  const _NoopFileDialogAdapter();

  @override
  Future<String?> pickDirectory({required String dialogTitle}) async => null;

  @override
  Future<String?> saveFile({
    required String dialogTitle,
    required String fileName,
  }) async {
    return null;
  }
}
