import 'package:sqflite/sqflite.dart';

class LamportClock {
  static const String _lamportKey = 'lamport';

  Future<int> ensureInitialized(DatabaseExecutor db) async {
    final List<Map<String, Object?>> rows = await db.query(
      'kv',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: const <Object?>[_lamportKey],
      limit: 1,
    );

    if (rows.isEmpty) {
      await db.insert('kv', {'key': _lamportKey, 'value': '1'});
      return 1;
    }

    return int.tryParse(rows.first['value']?.toString() ?? '') ?? 1;
  }

  Future<int> next(DatabaseExecutor db) async {
    final int current = await ensureInitialized(db);
    final int nextValue = current + 1;
    await db.update(
      'kv',
      {'value': '$nextValue'},
      where: 'key = ?',
      whereArgs: const <Object?>[_lamportKey],
    );
    return nextValue;
  }

  /// Reserve [count] lamport ticks in one KV update.
  /// Returns the previous lamport value, so next event starts from returned+1.
  Future<int> reserve(DatabaseExecutor db, int count) async {
    final int current = await ensureInitialized(db);
    final int newValue = current + count;
    await db.update(
      'kv',
      {'value': '$newValue'},
      where: 'key = ?',
      whereArgs: const <Object?>[_lamportKey],
    );
    return current;
  }
}
