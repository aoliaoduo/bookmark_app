import 'package:flutter_riverpod/legacy.dart';

import '../clock/app_clock.dart';
import '../db/app_database.dart';
import '../identity/device_identity_service.dart';
import 'change_log_repository.dart';
import 'sync_constants.dart';
import 'sync_engine.dart';
import 'sync_models.dart';
import 'sync_object_store.dart';
import 'webdav/webdav_config.dart';
import 'webdav/webdav_config_repository.dart';
import 'webdav/webdav_remote.dart';

class SyncRuntimeState {
  const SyncRuntimeState({
    required this.config,
    required this.syncState,
    required this.running,
    required this.testing,
    required this.status,
    required this.logs,
  });

  factory SyncRuntimeState.initial({required int nowMs}) {
    return SyncRuntimeState(
      config: WebDavConfig.empty,
      syncState: SyncState.empty(nowMs: nowMs),
      running: false,
      testing: false,
      status: '',
      logs: const <SyncLogEntry>[],
    );
  }

  final WebDavConfig config;
  final SyncState syncState;
  final bool running;
  final bool testing;
  final String status;
  final List<SyncLogEntry> logs;

  SyncRuntimeState copyWith({
    WebDavConfig? config,
    SyncState? syncState,
    bool? running,
    bool? testing,
    String? status,
    List<SyncLogEntry>? logs,
  }) {
    return SyncRuntimeState(
      config: config ?? this.config,
      syncState: syncState ?? this.syncState,
      running: running ?? this.running,
      testing: testing ?? this.testing,
      status: status ?? this.status,
      logs: logs ?? this.logs,
    );
  }
}

class SyncRuntimeService extends StateNotifier<SyncRuntimeState> {
  SyncRuntimeService({
    required this.database,
    required this.configRepository,
    required this.clock,
    required this.identityService,
  }) : super(SyncRuntimeState.initial(nowMs: clock.nowMs()));

  final AppDatabase database;
  final WebDavConfigRepository configRepository;
  final AppClock clock;
  final DeviceIdentityService identityService;

  Future<void> load() async {
    final WebDavConfig config = await configRepository.load();
    final SyncState syncState = await ChangeLogRepository(
      database.db,
    ).loadSyncState(nowMs: clock.nowMs());
    state = state.copyWith(config: config, syncState: syncState);
  }

  Future<void> saveConfig(WebDavConfig config) async {
    await configRepository.save(config);
    state = state.copyWith(config: config, status: '配置已保存');
  }

  Future<void> testConnection() async {
    if (state.testing) {
      return;
    }
    final WebDavConfig config = state.config;
    if (!config.isReady) {
      state = state.copyWith(status: '请先完整填写 WebDAV 配置');
      return;
    }
    state = state.copyWith(testing: true, status: '连接测试中...');
    try {
      final String deviceId = await identityService.getOrCreateDeviceId(
        database.db,
      );
      final WebDavRemote remote = WebDavRemote(config: config);
      await remote.ensureInitialized(deviceId: deviceId);
      await remote.pullChanges(currentDeviceId: deviceId, limit: 1);
      state = state.copyWith(testing: false, status: 'WebDAV 连接测试成功');
    } catch (error) {
      state = state.copyWith(testing: false, status: 'WebDAV 连接测试失败：$error');
    }
  }

  Future<SyncRunResult?> runManualSync() async {
    if (state.running) {
      return null;
    }
    final WebDavConfig config = state.config;
    if (!config.isReady) {
      state = state.copyWith(status: '请先完整填写 WebDAV 配置');
      return null;
    }
    state = state.copyWith(running: true, status: '同步中...');
    try {
      final SyncEngine engine = _buildEngine(config);
      final SyncRunResult result = await engine.syncOnce(force: false);
      final SyncState syncState = await ChangeLogRepository(
        database.db,
      ).loadSyncState(nowMs: clock.nowMs());
      state = state.copyWith(
        running: false,
        syncState: syncState,
        logs: engine.latestLogs(),
        status:
            result.message ??
            '同步完成：拉取${result.pulledCount}，应用${result.appliedCount}，推送${result.pushedCount}',
      );
      return result;
    } catch (error) {
      final SyncState syncState = await ChangeLogRepository(
        database.db,
      ).loadSyncState(nowMs: clock.nowMs());
      state = state.copyWith(
        running: false,
        syncState: syncState,
        status: '同步失败：$error',
      );
      return null;
    }
  }

  SyncEngine _buildEngine(WebDavConfig config) {
    return SyncEngine(
      changeLogRepository: ChangeLogRepository(database.db),
      objectStore: SyncObjectStore(database),
      remote: WebDavRemote(config: config),
      clock: clock,
      identityService: identityService,
      requestLimitPerWindow: config.paidPlan
          ? SyncConstants.paidPlanWindowLimit
          : SyncConstants.freePlanWindowLimit,
    );
  }
}
