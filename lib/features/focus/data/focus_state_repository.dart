import 'package:sqflite/sqflite.dart';

import '../../../core/db/app_database.dart';
import '../../../core/focus/focus_timer.dart';

class FocusStateRepository {
  FocusStateRepository(this.database);
  FocusStateRepository.inMemory() : database = null;

  static const String singletonId = 'singleton';
  final AppDatabase? database;
  FocusTimerSnapshot? _memorySnapshot;

  Future<FocusTimerSnapshot?> load() async {
    final AppDatabase? db = database;
    if (db == null) {
      return _memorySnapshot;
    }

    final List<Map<String, Object?>> rows = await db.db.query(
      'focus_state',
      where: 'id = ?',
      whereArgs: <Object?>[singletonId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    final Map<String, Object?> row = rows.first;
    final FocusMode mode = FocusModeDbCodec.fromDb(
      (row['mode'] as String?) ?? 'countdown',
    );
    final FocusPhase phase = FocusPhaseDbCodec.fromDb(
      (row['phase'] as String?) ?? 'idle',
    );
    final int? durationSeconds = _readNullableInt(row['duration_seconds']);
    final int focusDurationSeconds =
        mode == FocusMode.countdown &&
            (phase == FocusPhase.focus || phase == FocusPhase.idle) &&
            durationSeconds != null &&
            durationSeconds > 0
        ? durationSeconds
        : FocusTimerSnapshot.defaultFocusDurationSeconds;

    return FocusTimerSnapshot(
      mode: mode,
      phase: phase,
      focusDurationSeconds: focusDurationSeconds,
      startedAtMs: _readNullableInt(row['started_at']),
      durationSeconds: durationSeconds,
      elapsedSeconds: _readInt(row['elapsed_seconds'], fallback: 0),
      focusRatioNum: _readInt(row['focus_ratio_num'], fallback: 5),
      focusRatioDen: _readInt(row['focus_ratio_den'], fallback: 1),
      updatedAtMs: _readInt(row['updated_at'], fallback: 0),
    );
  }

  Future<void> save(FocusTimerSnapshot snapshot) async {
    final AppDatabase? db = database;
    if (db == null) {
      _memorySnapshot = snapshot;
      return;
    }

    final int? persistedDurationSeconds = switch (snapshot.phase) {
      FocusPhase.idle when snapshot.mode == FocusMode.countdown =>
        snapshot.focusDurationSeconds,
      _ => snapshot.durationSeconds,
    };
    await db.db.insert('focus_state', <String, Object?>{
      'id': singletonId,
      'mode': snapshot.mode.dbValue,
      'phase': snapshot.phase.dbValue,
      'started_at': snapshot.startedAtMs,
      'duration_seconds': persistedDurationSeconds,
      'elapsed_seconds': snapshot.elapsedSeconds,
      'focus_ratio_num': snapshot.focusRatioNum,
      'focus_ratio_den': snapshot.focusRatioDen,
      'updated_at': snapshot.updatedAtMs,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  int _readInt(Object? raw, {required int fallback}) {
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    return fallback;
  }

  int? _readNullableInt(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    return null;
  }
}
