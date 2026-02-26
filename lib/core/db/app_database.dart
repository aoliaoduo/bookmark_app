import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'migrations.dart';

/// Todo priority encoding (PRD v1.1):
/// 2=high, 1=medium, 0=low
abstract final class TodoPriorityCode {
  static const int high = 2;
  static const int medium = 1;
  static const int low = 0;
}

/// Todo status encoding (PRD v1.1):
/// 0=open, 1=done
abstract final class TodoStatusCode {
  static const int open = 0;
  static const int done = 1;
}

class AppDatabase {
  AppDatabase._(this.db);

  static const String _dbFileName = 'app.db';
  static final Logger _log = Logger('AppDatabase');

  final Database db;
  bool _ftsSelfCheckRan = false;

  static Future<AppDatabase> open({String? databasePath}) async {
    _setupFactoryForPlatform();
    final String resolvedPath =
        databasePath ?? await _defaultDatabasePath(_dbFileName);

    final Database database = await openDatabase(
      resolvedPath,
      version: kCurrentDbVersion,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
      onOpen: (Database db) async {
        final List<Map<String, Object?>> rows = await db.rawQuery(
          'PRAGMA user_version;',
        );
        final Object? userVersion = rows.firstOrNull?['user_version'];
        _log.info('数据库打开：path=$resolvedPath, user_version=$userVersion');
      },
    );

    final AppDatabase appDatabase = AppDatabase._(database);
    await appDatabase.runFtsSelfCheckOnce();
    return appDatabase;
  }

  Future<void> runFtsSelfCheckOnce() async {
    if (_ftsSelfCheckRan) {
      return;
    }

    _ftsSelfCheckRan = true;
    try {
      await db.insert('search_fts', <String, Object?>{
        'entity_type': 'selfcheck',
        'entity_id': '1',
        'title': 'fts selfcheck',
        'body': 'hello',
        'tags': 'test',
      });

      final List<Map<String, Object?>> rows = await db.rawQuery(
        "SELECT entity_id FROM search_fts WHERE search_fts MATCH 'hello' LIMIT 1;",
      );

      if (rows.isNotEmpty && rows.first['entity_id']?.toString() == '1') {
        _log.info('FTS5 OK');
      } else {
        _log.warning('FTS5 自检未通过：未查到预期结果');
      }
    } catch (error, stackTrace) {
      _log.warning('FTS5 自检失败：$error\n$stackTrace');
    } finally {
      try {
        await db.delete(
          'search_fts',
          where: 'entity_type = ? AND entity_id = ?',
          whereArgs: <Object?>['selfcheck', '1'],
        );
      } catch (cleanupError) {
        _log.warning('FTS5 自检清理失败：$cleanupError');
      }
    }
  }

  Future<void> close() => db.close();

  static Future<String> _defaultDatabasePath(String dbFileName) async {
    final Directory supportDir = await getApplicationSupportDirectory();
    if (!supportDir.existsSync()) {
      supportDir.createSync(recursive: true);
    }
    return p.join(supportDir.path, dbFileName);
  }

  static void _setupFactoryForPlatform() {
    if (Platform.isWindows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }
}
