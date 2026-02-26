import 'dart:io';

import 'package:code/core/db/app_database.dart';
import 'package:code/core/focus/focus_timer.dart';
import 'package:code/features/focus/data/focus_state_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'restore from focus_state keeps remaining time by wall-clock delta',
    () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'focus_restore_',
      );
      final String dbPath = p.join(tempDir.path, 'focus.db');
      final AppDatabase appDatabase = await AppDatabase.open(
        databasePath: dbPath,
      );
      final FocusStateRepository repository = FocusStateRepository(appDatabase);

      const int startedAt = 1_000_000;
      const int elapsedBeforeRestart = 120;
      const int focusDuration = 1500;
      const int restartNow = startedAt + 300 * 1000;
      final FocusTimerSnapshot runningFocus = FocusTimerSnapshot(
        mode: FocusMode.countdown,
        phase: FocusPhase.focus,
        focusDurationSeconds: focusDuration,
        startedAtMs: startedAt,
        durationSeconds: focusDuration,
        elapsedSeconds: elapsedBeforeRestart,
        focusRatioNum: 5,
        focusRatioDen: 1,
        updatedAtMs: startedAt,
      );
      await repository.save(runningFocus);

      final FocusTimerSnapshot loaded = (await repository.load())!;
      final FocusTimerSnapshot restored = FocusTimerMachine.reconcile(
        loaded,
        nowMs: restartNow,
      );

      expect(restored.phase, FocusPhase.focus);
      expect(restored.remainingAt(restartNow), focusDuration - 420);

      await appDatabase.close();
      await tempDir.delete(recursive: true);
    },
  );
}
