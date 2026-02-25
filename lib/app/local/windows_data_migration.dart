import 'dart:io';

import 'package:path/path.dart' as p;

import '../../platform/platform_adapter.dart';
import '../../platform/platform_services.dart';

class WindowsDataMigration {
  static const List<String> _filesToMigrate = <String>[
    'bookmark_app.db',
    'bookmark_app.db-wal',
    'bookmark_app.db-shm',
    'shared_preferences.json',
    'flutter_secure_storage.dat',
  ];

  static Future<void> migrateLegacyBookmarkAppData() async {
    final PlatformAdapter platform = PlatformServices.instance.platform;
    if (!platform.capabilities.isWindows) {
      return;
    }

    final Directory currentDir = Directory(
      await platform.getApplicationSupportPath(),
    );
    final Directory legacyDir = Directory(
      p.join(p.dirname(currentDir.path), 'bookmark_app'),
    );

    final String currentPath = p.normalize(currentDir.path).toLowerCase();
    final String legacyPath = p.normalize(legacyDir.path).toLowerCase();
    if (currentPath == legacyPath) {
      return;
    }

    if (!await legacyDir.exists()) {
      return;
    }

    await currentDir.create(recursive: true);

    for (final String fileName in _filesToMigrate) {
      await _migrateFile(
        source: File(p.join(legacyDir.path, fileName)),
        target: File(p.join(currentDir.path, fileName)),
      );
    }
  }

  static Future<void> _migrateFile({
    required File source,
    required File target,
  }) async {
    if (!await source.exists()) {
      return;
    }

    bool shouldCopy = !await target.exists();
    if (!shouldCopy) {
      final int sourceSize = await source.length();
      final int targetSize = await target.length();
      final DateTime sourceModifiedAt = await source.lastModified();
      final DateTime targetModifiedAt = await target.lastModified();
      shouldCopy = sourceSize != targetSize ||
          sourceModifiedAt.isAfter(targetModifiedAt);
    }

    if (!shouldCopy) {
      return;
    }

    await source.copy(target.path);
  }
}
