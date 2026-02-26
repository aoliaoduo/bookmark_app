import 'dart:io';

import 'package:code/core/db/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppDatabase', () {
    test('creates required tables and supports FTS MATCH', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'db_test_',
      );
      final String dbPath = p.join(tempDir.path, 'test.db');

      final AppDatabase appDatabase = await AppDatabase.open(
        databasePath: dbPath,
      );

      const List<String> requiredTables = <String>[
        'kv',
        'inbox_drafts',
        'tags',
        'entity_tags',
        'todos',
        'notes',
        'note_versions',
        'bookmarks',
        'focus_state',
        'change_log',
        'processed_changes',
        'sync_state',
        'notification_jobs',
        'search_fts',
      ];

      for (final String tableName in requiredTables) {
        final List<Map<String, Object?>> rows = await appDatabase.db.rawQuery(
          "SELECT name FROM sqlite_master WHERE name = ? LIMIT 1;",
          <Object?>[tableName],
        );
        expect(rows, isNotEmpty, reason: 'missing table: $tableName');
      }

      await appDatabase.db.insert('search_fts', <String, Object?>{
        'entity_type': 'note',
        'entity_id': 'n1',
        'title': 'demo title',
        'body': 'hello world',
        'tags': 'demo',
      });

      final List<Map<String, Object?>> hits = await appDatabase.db.rawQuery(
        "SELECT entity_id FROM search_fts WHERE search_fts MATCH 'hello' LIMIT 1;",
      );

      expect(hits, isNotEmpty);
      expect(hits.first['entity_id'], 'n1');

      await appDatabase.close();
      await tempDir.delete(recursive: true);
    });
  });
}
