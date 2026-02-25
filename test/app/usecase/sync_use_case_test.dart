import 'dart:async';

import 'package:bookmark_app/app/settings/app_settings.dart';
import 'package:bookmark_app/app/sync_coordinator.dart';
import 'package:bookmark_app/app/usecase/sync_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializes sync and backup jobs in one gate', () async {
    final Completer<void> syncStarted = Completer<void>();
    final Completer<void> backupStarted = Completer<void>();
    final Completer<void> allowSyncFinish = Completer<void>();
    final _FakeSyncGateway gateway = _FakeSyncGateway(
      onSync: (AppSettings _) async {
        syncStarted.complete();
        await allowSyncFinish.future;
        return _successReport();
      },
      onBackup: (AppSettings _) async {
        backupStarted.complete();
      },
    );
    final SyncUseCase useCase = SyncUseCase(gateway: gateway);
    addTearDown(useCase.dispose);

    final SyncTaskHandle<SyncRunDiagnostics> syncHandle = useCase.enqueueSync(
      settings: _settings(),
    );
    final SyncTaskHandle<void> backupHandle = useCase.enqueueBackupSnapshot(
      settings: _settings(),
    );

    await syncStarted.future;
    expect(useCase.runningJobKind, SyncJobKind.sync);
    expect(useCase.queuedJobCount, 1);

    allowSyncFinish.complete();
    await syncHandle.result;
    await backupStarted.future;
    await backupHandle.result;

    expect(gateway.syncCalls, 1);
    expect(gateway.backupCalls, 1);
  });

  test('can cancel queued job before it starts', () async {
    final Completer<void> syncStarted = Completer<void>();
    final Completer<void> allowSyncFinish = Completer<void>();
    final _FakeSyncGateway gateway = _FakeSyncGateway(
      onSync: (AppSettings _) async {
        syncStarted.complete();
        await allowSyncFinish.future;
        return _successReport();
      },
      onBackup: (AppSettings _) async {},
    );
    final SyncUseCase useCase = SyncUseCase(gateway: gateway);
    addTearDown(useCase.dispose);

    final SyncTaskHandle<SyncRunDiagnostics> syncHandle = useCase.enqueueSync(
      settings: _settings(),
    );
    final SyncTaskHandle<void> backupHandle = useCase.enqueueBackupSnapshot(
      settings: _settings(),
    );
    final Future<void> canceledBackup = backupHandle.result.then(
      (_) => fail('queued backup should have been canceled'),
      onError: (Object error) {
        expect(error, isA<SyncTaskCanceledException>());
      },
    );

    await syncStarted.future;
    expect(backupHandle.cancel(), isTrue);

    allowSyncFinish.complete();
    await syncHandle.result;
    await canceledBackup;
    expect(gateway.backupCalls, 0);
  });

  test('deduplicates same queueTag for auto sync', () async {
    final Completer<void> allowSyncFinish = Completer<void>();
    final _FakeSyncGateway gateway = _FakeSyncGateway(
      onSync: (AppSettings _) async {
        await allowSyncFinish.future;
        return _successReport();
      },
      onBackup: (AppSettings _) async {},
    );
    final SyncUseCase useCase = SyncUseCase(gateway: gateway);
    addTearDown(useCase.dispose);

    final SyncTaskHandle<SyncRunDiagnostics> first = useCase.enqueueSync(
      settings: _settings(),
      queueTag: 'auto-sync',
    );
    final SyncTaskHandle<SyncRunDiagnostics> second = useCase.enqueueSync(
      settings: _settings(),
      queueTag: 'auto-sync',
    );

    expect(second.id, first.id);

    allowSyncFinish.complete();
    await first.result;
    expect(gateway.syncCalls, 1);
  });
}

AppSettings _settings() {
  return const AppSettings(
    deviceId: 'device-1',
    titleRefreshDays: 7,
    autoRefreshOnLaunch: false,
    autoSyncOnLaunch: true,
    autoSyncOnChange: true,
    webDavEnabled: true,
    webDavBaseUrl: 'https://dav.example.com',
    webDavUserId: 'user-1',
    webDavUsername: 'u',
    webDavPassword: 'p',
  );
}

SyncRunDiagnostics _successReport() {
  final DateTime at = DateTime.utc(2026, 2, 25, 0, 0, 0);
  return SyncRunDiagnostics(
    startedAt: at,
    finishedAt: at,
    attemptCount: 1,
    success: true,
    engineReport: null,
    errorMessage: null,
  );
}

class _FakeSyncGateway implements SyncGateway {
  _FakeSyncGateway({
    required this.onSync,
    required this.onBackup,
  });

  final Future<SyncRunDiagnostics> Function(AppSettings settings) onSync;
  final Future<void> Function(AppSettings settings) onBackup;
  int syncCalls = 0;
  int backupCalls = 0;
  int markdownBackupCalls = 0;

  @override
  Future<void> backupNow(AppSettings settings) async {
    backupCalls += 1;
    await onBackup(settings);
  }

  @override
  Future<void> backupMarkdownNow({
    required AppSettings settings,
    required String markdown,
  }) async {
    markdownBackupCalls += 1;
    await onBackup(settings);
  }

  @override
  Future<SyncRunDiagnostics> syncNow(AppSettings settings) async {
    syncCalls += 1;
    return onSync(settings);
  }
}
