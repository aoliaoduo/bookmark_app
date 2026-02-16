import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class WindowsDataMigration {
  static const List<String> _filesToMigrate = <String>[
    'bookmark_app.db',
    'shared_preferences.json',
    'flutter_secure_storage.dat',
  ];

  static Future<void> migrateLegacyBookmarkAppData() async {
    if (!Platform.isWindows) {
      return;
    }

    final Directory currentDir = await getApplicationSupportDirectory();
    final Directory legacyDir = Directory(
      p.join(currentDir.parent.path, 'bookmark_app'),
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
      shouldCopy = sourceSize > targetSize;
    }

    if (!shouldCopy) {
      return;
    }

    await source.copy(target.path);
  }
}
