import 'dart:io';

import 'package:code/core/db/app_database.dart';
import 'package:code/core/search/fts_updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fts updater makes todo searchable', () async {
    final Directory dir = await Directory.systemTemp.createTemp('fts_updater_');
    final String dbPath = p.join(dir.path, 'fts.db');

    final AppDatabase db = await AppDatabase.open(databasePath: dbPath);
    final FtsUpdater updater = FtsUpdater();

    await db.db.insert('todos', {
      'id': 'todo-1',
      'title': '学习 Flutter FTS',
      'priority': 1,
      'status': 0,
      'remind_at': null,
      'created_at': 1,
      'updated_at': 1,
      'deleted': 0,
      'lamport': 1,
      'device_id': 'device',
    });

    await updater.upsertTodo(db.db, 'todo-1');

    final rows = await db.db.rawQuery(
      "SELECT entity_id FROM search_fts WHERE search_fts MATCH 'Flutter' LIMIT 1;",
    );
    expect(rows, isNotEmpty);
    expect(rows.first['entity_id'], 'todo-1');

    await db.close();
    await dir.delete(recursive: true);
  });
}
