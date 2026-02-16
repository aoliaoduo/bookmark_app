import 'package:bookmark_app/app/maintenance/maintenance_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  test('slimDown runs PRAGMA via rawQuery and keeps VACUUM as execute',
      () async {
    final _FakeDatabase db = _FakeDatabase(journalMode: 'wal');
    final MaintenanceService service = MaintenanceService(db: db);

    final SlimDownResult result = await service.slimDown(
      outboxRetention: const Duration(days: 1),
      trashRetention: const Duration(days: 1),
    );

    expect(result.purgedOutboxRows, 2);
    expect(result.purgedTrashRows, 3);
    expect(result.purgedInvalidRows, 1);
    expect(db.rawQueries, contains('PRAGMA journal_mode'));
    expect(db.rawQueries, contains('PRAGMA wal_checkpoint(TRUNCATE)'));
    expect(db.rawQueries, contains('PRAGMA optimize'));
    expect(db.executedStatements, <String>['VACUUM']);
  });

  test('slimDown skips wal checkpoint when journal mode is not wal', () async {
    final _FakeDatabase db = _FakeDatabase(journalMode: 'delete');
    final MaintenanceService service = MaintenanceService(db: db);

    await service.slimDown();

    expect(db.rawQueries, contains('PRAGMA journal_mode'));
    expect(db.rawQueries, isNot(contains('PRAGMA wal_checkpoint(TRUNCATE)')));
  });

  test('slimDown tolerates wal checkpoint failure on mobile', () async {
    final _FakeDatabase db = _FakeDatabase(
      journalMode: 'wal',
      failWalCheckpoint: true,
    );
    final MaintenanceService service = MaintenanceService(db: db);

    await service.slimDown();

    expect(db.rawQueries, contains('PRAGMA wal_checkpoint(TRUNCATE)'));
    expect(db.executedStatements, contains('VACUUM'));
  });
}

class _FakeDatabase implements Database {
  _FakeDatabase({
    required this.journalMode,
    this.failWalCheckpoint = false,
  });

  final String journalMode;
  final bool failWalCheckpoint;
  final List<String> rawQueries = <String>[];
  final List<String> executedStatements = <String>[];

  @override
  String get path => 'not_exists.db';

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isMethod && invocation.memberName == #delete) {
      final String table = invocation.positionalArguments[0] as String;
      final String? where = invocation.namedArguments[#where] as String?;

      if (table == 'sync_outbox') {
        return Future<int>.value(2);
      }
      if (table == 'bookmarks' &&
          where != null &&
          where.contains('deleted_at IS NOT NULL')) {
        return Future<int>.value(3);
      }
      if (table == 'bookmarks' &&
          where != null &&
          where.contains("trim(url) = ''")) {
        return Future<int>.value(1);
      }
      return Future<int>.value(0);
    }

    if (invocation.isMethod && invocation.memberName == #rawQuery) {
      final String sql = invocation.positionalArguments[0] as String;
      rawQueries.add(sql);

      if (sql == 'PRAGMA journal_mode') {
        return Future<List<Map<String, Object?>>>.value(
          <Map<String, Object?>>[
            <String, Object?>{'journal_mode': journalMode},
          ],
        );
      }
      if (sql == 'PRAGMA wal_checkpoint(TRUNCATE)' && failWalCheckpoint) {
        throw Exception(
          'Queries can be performed using SQLiteDatabase query or rawQuery methods only.',
        );
      }
      return Future<List<Map<String, Object?>>>.value(
        const <Map<String, Object?>>[],
      );
    }

    if (invocation.isMethod && invocation.memberName == #execute) {
      final String sql = invocation.positionalArguments[0] as String;
      executedStatements.add(sql);
      return Future<void>.value();
    }

    return super.noSuchMethod(invocation);
  }
}
