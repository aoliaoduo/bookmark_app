import 'dart:io';

import 'package:code/core/db/app_database.dart';
import 'package:code/core/theme/theme_models.dart';
import 'package:code/core/theme/theme_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('theme repository save/load roundtrip', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'theme_repo_test_',
    );
    final String dbPath = p.join(tempDir.path, 'theme.db');
    final AppDatabase db = await AppDatabase.open(databasePath: dbPath);
    final ThemeRepository repository = ThemeRepository(db);

    await repository.save(
      const ThemeSelection(mode: AppThemeMode.dark, presetId: 'claude'),
    );
    final ThemeSelection loaded = await repository.load();
    expect(loaded.mode, AppThemeMode.dark);
    expect(loaded.presetId, 'claude');

    await db.close();
    await tempDir.delete(recursive: true);
  });
}
