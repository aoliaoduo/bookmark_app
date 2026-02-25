import 'dart:async';

import 'package:bookmark_app/app/app_controller.dart';
import 'package:bookmark_app/app/export/export_service.dart';
import 'package:bookmark_app/app/local/bookmark_repository.dart';
import 'package:bookmark_app/app/maintenance/maintenance_service.dart';
import 'package:bookmark_app/app/settings/app_settings.dart';
import 'package:bookmark_app/app/settings/settings_store.dart';
import 'package:bookmark_app/app/sync_coordinator.dart';
import 'package:bookmark_app/core/metadata/metadata_fetch_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'runStartupSyncIfNeeded skips sync and markdown backup when autoSyncOnLaunch is off',
    () async {
      final _Harness harness = await _createHarness(autoSyncOnLaunch: false);
      addTearDown(harness.dispose);

      final bool success = await harness.controller.runStartupSyncIfNeeded();

      expect(success, isFalse);
      expect(harness.syncCoordinator.syncCalls, 0);
      expect(harness.syncCoordinator.markdownBackupCalls, 0);
    },
  );

  test(
    'runStartupSyncIfNeeded runs once when autoSyncOnLaunch is on',
    () async {
      final _Harness harness = await _createHarness(autoSyncOnLaunch: true);
      addTearDown(harness.dispose);

      final bool first = await harness.controller.runStartupSyncIfNeeded();
      final bool second = await harness.controller.runStartupSyncIfNeeded();

      expect(first, isTrue);
      expect(second, isFalse);
      expect(harness.syncCoordinator.syncCalls, 1);
      expect(harness.syncCoordinator.markdownBackupCalls, 1);
    },
  );

  test(
    'runStartupSyncIfNeeded skips markdown backup when startup sync fails',
    () async {
      final _Harness harness = await _createHarness(
        autoSyncOnLaunch: true,
        syncShouldSucceed: false,
      );
      addTearDown(harness.dispose);

      final bool success = await harness.controller.runStartupSyncIfNeeded();

      expect(success, isFalse);
      expect(harness.syncCoordinator.syncCalls, 1);
      expect(harness.syncCoordinator.markdownBackupCalls, 0);
    },
  );

  test('initialize enters ready state when bootstrap succeeds', () async {
    final _Harness harness = await _createHarness(autoSyncOnLaunch: false);
    addTearDown(harness.dispose);

    expect(harness.controller.bootstrapState, AppBootstrapState.ready);
    expect(harness.controller.bootstrapMessage, isNull);
  });

  test('initialize rethrows when loading settings fails', () async {
    final Database db = await _openDb();
    final BookmarkRepository repository = BookmarkRepository(
      db: db,
      metadataService: MetadataFetchService(),
      deviceId: 'device-1',
    );
    final AppController controller = AppController(
      repository: repository,
      settingsStore: _ThrowingSettingsStore(Exception('forced load failure')),
      exportService: ExportService(),
      maintenanceService: MaintenanceService(db: db),
      syncCoordinator: _RecordingSyncCoordinator(
        repository: repository,
        syncShouldSucceed: true,
      ),
    );
    addTearDown(() async {
      controller.dispose();
      await db.close();
    });

    await expectLater(controller.initialize(), throwsException);
    expect(controller.bootstrapState, AppBootstrapState.failed);
    expect(controller.error, contains('forced load failure'));
    expect(() => controller.settings, throwsStateError);
  });

  test('syncNow queues behind backupNow and runs after backup finishes',
      () async {
    final _Harness harness = await _createHarness(autoSyncOnLaunch: false);
    addTearDown(harness.dispose);

    final Completer<void> backupStarted = Completer<void>();
    final Completer<void> allowBackupFinish = Completer<void>();
    harness.syncCoordinator.backupStarted = backupStarted;
    harness.syncCoordinator.allowBackupFinish = allowBackupFinish;

    final Future<void> backupFuture = harness.controller.backupNow();
    await backupStarted.future;

    final Future<bool> syncFuture = harness.controller.syncNow();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(harness.syncCoordinator.syncCalls, 0);

    allowBackupFinish.complete();
    await backupFuture;

    final bool syncResult = await syncFuture;
    expect(syncResult, isTrue);
    expect(harness.syncCoordinator.syncCalls, 1);
    expect(harness.controller.error, isNull);
  });

  test('syncNow masks sensitive fields in sync errors', () async {
    final _Harness harness = await _createHarness(
      autoSyncOnLaunch: false,
      syncShouldSucceed: false,
      syncErrorMessage:
          'WebDAV pull failed url=https://u:pw@dav.example.com/x?token=abc&password=xyz Authorization: Basic dXNlcjpwYXNz',
    );
    addTearDown(harness.dispose);

    final bool success = await harness.controller.syncNow(userInitiated: true);

    expect(success, isFalse);
    final String? syncError = harness.controller.syncError;
    expect(syncError, isNotNull);
    expect(syncError, contains('Basic ***'));
    expect(syncError, contains('token=***'));
    expect(syncError, contains('password=***'));
    expect(syncError, isNot(contains('dXNlcjpwYXNz')));
    expect(syncError, isNot(contains('token=abc')));
    expect(syncError, isNot(contains('password=xyz')));
  });
}

Future<_Harness> _createHarness({
  required bool autoSyncOnLaunch,
  bool autoSyncOnChange = false,
  bool syncShouldSucceed = true,
  String? syncErrorMessage,
}) async {
  final Database db = await _openDb();
  final AppSettings settings = _buildSettings(
    autoSyncOnLaunch: autoSyncOnLaunch,
    autoSyncOnChange: autoSyncOnChange,
  );
  final BookmarkRepository repository = BookmarkRepository(
    db: db,
    metadataService: MetadataFetchService(),
    deviceId: settings.deviceId,
  );
  final _FakeSettingsStore settingsStore = _FakeSettingsStore(settings);
  final _RecordingSyncCoordinator syncCoordinator = _RecordingSyncCoordinator(
    repository: repository,
    syncShouldSucceed: syncShouldSucceed,
    syncErrorMessage: syncErrorMessage,
  );
  final AppController controller = AppController(
    repository: repository,
    settingsStore: settingsStore,
    exportService: ExportService(),
    maintenanceService: MaintenanceService(db: db),
    syncCoordinator: syncCoordinator,
  );
  await controller.initialize();
  return _Harness(
    db: db,
    controller: controller,
    syncCoordinator: syncCoordinator,
  );
}

AppSettings _buildSettings({
  required bool autoSyncOnLaunch,
  bool autoSyncOnChange = false,
}) {
  return AppSettings(
    deviceId: 'device-1',
    titleRefreshDays: 7,
    autoRefreshOnLaunch: false,
    autoSyncOnLaunch: autoSyncOnLaunch,
    autoSyncOnChange: autoSyncOnChange,
    webDavEnabled: true,
    webDavBaseUrl: 'https://dav.example.com',
    webDavUserId: 'user-1',
    webDavUsername: 'u',
    webDavPassword: 'p',
  );
}

class _Harness {
  _Harness({
    required this.db,
    required this.controller,
    required this.syncCoordinator,
  });

  final Database db;
  final AppController controller;
  final _RecordingSyncCoordinator syncCoordinator;

  Future<void> dispose() async {
    controller.dispose();
    await db.close();
  }
}

class _FakeSettingsStore extends SettingsStore {
  _FakeSettingsStore(this._settings);

  AppSettings _settings;

  @override
  Future<AppSettings> load() async => _settings;

  @override
  Future<void> save(AppSettings settings) async {
    _settings = settings;
  }

  @override
  Future<void> clearAll() async {}
}

class _ThrowingSettingsStore extends SettingsStore {
  _ThrowingSettingsStore(this._error);

  final Object _error;

  @override
  Future<AppSettings> load() {
    return Future<AppSettings>.error(_error);
  }

  @override
  Future<void> save(AppSettings settings) async {}

  @override
  Future<void> clearAll() async {}
}

class _RecordingSyncCoordinator extends SyncCoordinator {
  _RecordingSyncCoordinator({
    required super.repository,
    required this.syncShouldSucceed,
    this.syncErrorMessage,
  });

  int syncCalls = 0;
  int backupCalls = 0;
  int markdownBackupCalls = 0;
  final bool syncShouldSucceed;
  final String? syncErrorMessage;
  Completer<void>? backupStarted;
  Completer<void>? allowBackupFinish;

  @override
  Future<void> backupNow(AppSettings settings) async {
    backupCalls += 1;
    if (!(backupStarted?.isCompleted ?? true)) {
      backupStarted!.complete();
    }
    final Completer<void>? gate = allowBackupFinish;
    if (gate != null) {
      await gate.future;
    }
  }

  @override
  Future<SyncRunDiagnostics> syncNow(AppSettings settings) async {
    syncCalls += 1;
    final DateTime at = DateTime.utc(2026, 2, 25, 0, 0, 0);
    return SyncRunDiagnostics(
      startedAt: at,
      finishedAt: at,
      attemptCount: 1,
      success: syncShouldSucceed,
      engineReport: null,
      errorMessage: syncShouldSucceed
          ? null
          : (syncErrorMessage ?? 'forced startup sync failure'),
    );
  }

  @override
  Future<void> backupMarkdownNow({
    required AppSettings settings,
    required String markdown,
  }) async {
    markdownBackupCalls += 1;
  }
}

Future<Database> _openDb() {
  return openDatabase(
    inMemoryDatabasePath,
    version: 1,
    onCreate: (Database db, int _) async {
      await db.execute('''
CREATE TABLE bookmarks(
  id TEXT PRIMARY KEY,
  url TEXT NOT NULL,
  normalized_url TEXT NOT NULL,
  title TEXT,
  note TEXT,
  tags_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  title_updated_at TEXT
)
''');
      await db.execute('''
CREATE TABLE sync_outbox(
  op_id TEXT PRIMARY KEY,
  op_type TEXT NOT NULL,
  bookmark_id TEXT,
  bookmark_json TEXT NOT NULL,
  occurred_at TEXT NOT NULL,
  device_id TEXT NOT NULL,
  pushed INTEGER NOT NULL DEFAULT 0
)
''');
      await db.execute('''
CREATE TABLE sync_state(
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
)
''');
      await db.execute('''
CREATE TABLE sync_tombstones(
  bookmark_id TEXT PRIMARY KEY,
  deleted_at TEXT NOT NULL,
  expire_at TEXT NOT NULL
)
''');
    },
  );
}
