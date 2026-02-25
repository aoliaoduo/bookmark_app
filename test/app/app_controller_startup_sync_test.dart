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
}

Future<_Harness> _createHarness({required bool autoSyncOnLaunch}) async {
  final Database db = await _openDb();
  final AppSettings settings = _buildSettings(
    autoSyncOnLaunch: autoSyncOnLaunch,
  );
  final BookmarkRepository repository = BookmarkRepository(
    db: db,
    metadataService: MetadataFetchService(),
    deviceId: settings.deviceId,
  );
  final _FakeSettingsStore settingsStore = _FakeSettingsStore(settings);
  final _RecordingSyncCoordinator syncCoordinator = _RecordingSyncCoordinator(
    repository: repository,
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

AppSettings _buildSettings({required bool autoSyncOnLaunch}) {
  return AppSettings(
    deviceId: 'device-1',
    titleRefreshDays: 7,
    autoRefreshOnLaunch: false,
    autoSyncOnLaunch: autoSyncOnLaunch,
    autoSyncOnChange: false,
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

class _RecordingSyncCoordinator extends SyncCoordinator {
  _RecordingSyncCoordinator({required super.repository});

  int syncCalls = 0;
  int markdownBackupCalls = 0;

  @override
  Future<SyncRunDiagnostics> syncNow(AppSettings settings) async {
    syncCalls += 1;
    final DateTime at = DateTime.utc(2026, 2, 25, 0, 0, 0);
    return SyncRunDiagnostics(
      startedAt: at,
      finishedAt: at,
      attemptCount: 1,
      success: true,
      engineReport: null,
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
