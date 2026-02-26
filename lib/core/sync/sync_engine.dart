import 'dart:collection';

import 'package:logging/logging.dart';

import '../clock/app_clock.dart';
import '../identity/device_identity_service.dart';
import 'change_log_repository.dart';
import 'sync_constants.dart';
import 'sync_models.dart';
import 'sync_object_store.dart';
import 'remote/sync_remote.dart';

class SyncRemoteException implements Exception {
  const SyncRemoteException({required this.message, this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'SyncRemoteException(status=$statusCode, $message)';
}

class SyncEngine {
  SyncEngine({
    required this.changeLogRepository,
    required this.objectStore,
    required this.remote,
    required this.clock,
    required this.identityService,
  });

  static final Logger _log = Logger('SyncEngine');

  final ChangeLogRepository changeLogRepository;
  final SyncObjectStore objectStore;
  final SyncRemote remote;
  final AppClock clock;
  final DeviceIdentityService identityService;
  final ListQueue<SyncLogEntry> _logs = ListQueue<SyncLogEntry>();

  List<SyncLogEntry> latestLogs({int max = 60}) {
    return _logs.takeLast(max).toList(growable: false);
  }

  Future<SyncRunResult> syncOnce({
    bool force = false,
    int budget = SyncConstants.defaultChangeBudgetPerSync,
  }) async {
    final int nowMs = clock.nowMs();
    SyncState state = await changeLogRepository.loadSyncState(nowMs: nowMs);

    if (!force &&
        state.nextAllowedSyncAt != null &&
        nowMs < state.nextAllowedSyncAt!) {
      _appendLog(
        'INFO',
        '同步节流：距离下次同步还剩 ${(state.nextAllowedSyncAt! - nowMs) ~/ 1000}s',
      );
      return const SyncRunResult(
        pulledCount: 0,
        appliedCount: 0,
        pushedCount: 0,
        skippedByThrottle: true,
        skippedByBackoff: false,
        message: '同步节流中',
      );
    }

    if (!force && state.backoffUntil != null && nowMs < state.backoffUntil!) {
      _appendLog('WARN', '同步退避中：将于 ${state.backoffUntil} 后重试');
      return const SyncRunResult(
        pulledCount: 0,
        appliedCount: 0,
        pushedCount: 0,
        skippedByThrottle: false,
        skippedByBackoff: true,
        message: '退避中',
      );
    }

    final _RequestBudgetCounter requestBudget = _RequestBudgetCounter.fromState(
      state,
      nowMs: nowMs,
      limitPerWindow: SyncConstants.freePlanWindowLimit,
      windowMs: SyncConstants.requestWindowMinutes * 60 * 1000,
    );
    if (requestBudget.reachedLimit) {
      final int nextAt = requestBudget.windowStartedAt + requestBudget.windowMs;
      state = state.copyWith(
        backoffUntil: nextAt,
        lastError: '请求预算已耗尽，等待窗口重置',
        updatedAt: nowMs,
      );
      await changeLogRepository.saveSyncState(state);
      _appendLog('WARN', '请求预算耗尽，等待窗口重置');
      return const SyncRunResult(
        pulledCount: 0,
        appliedCount: 0,
        pushedCount: 0,
        skippedByThrottle: false,
        skippedByBackoff: true,
        message: '请求预算耗尽',
      );
    }

    state = state.copyWith(
      lastSyncStartedAt: nowMs,
      nextAllowedSyncAt: nowMs + SyncConstants.throttleSeconds * 1000,
      requestWindowStartedAt: requestBudget.windowStartedAt,
      requestCountInWindow: requestBudget.usedCount,
      updatedAt: nowMs,
    );
    await changeLogRepository.saveSyncState(state);

    try {
      final String deviceId = await identityService.getOrCreateDeviceId(
        objectStore.database.db,
      );

      requestBudget.consume(1);
      await remote.ensureInitialized(deviceId: deviceId);

      requestBudget.consume(1);
      final List<SyncChange> remoteChanges = await remote.pullChanges(
        currentDeviceId: deviceId,
        limit: budget,
        afterChangeId: state.lastAppliedChangeId,
      );

      int appliedCount = 0;
      String? lastAppliedId = state.lastAppliedChangeId;
      for (final SyncChange change in remoteChanges) {
        if (await changeLogRepository.isRemoteProcessed(change.id)) {
          continue;
        }
        SyncObject? remoteObject;
        if (change.operation == SyncOperation.upsert) {
          requestBudget.consume(1);
          remoteObject = await remote.getObject(
            entityType: change.entityType,
            entityId: change.entityId,
          );
        }
        final SyncObject effective =
            remoteObject ??
            SyncObject(
              entityType: change.entityType,
              entityId: change.entityId,
              lamport: change.lamport,
              deviceId: change.deviceId,
              deleted: true,
              content: const <String, Object?>{},
            );
        await objectStore.applyRemoteObject(effective);
        await changeLogRepository.markRemoteProcessed(
          changeId: change.id,
          sourceDeviceId: change.deviceId,
          appliedAt: nowMs,
        );
        appliedCount += 1;
        lastAppliedId = change.id;
      }

      final List<SyncChange> pending = await changeLogRepository.listPending(
        limit: budget,
      );
      final List<String> syncedIds = <String>[];
      String? lastPushedId = state.lastPushedChangeId;
      int maxLamport = 0;
      for (final SyncChange change in pending) {
        maxLamport = change.lamport > maxLamport ? change.lamport : maxLamport;
        final SyncObject? object = await objectStore.buildObjectForChange(
          change,
        );
        if (object != null) {
          requestBudget.consume(1);
          await remote.putObject(object);
        }
        requestBudget.consume(1);
        await remote.putChange(change);
        syncedIds.add(change.id);
        lastPushedId = change.id;
      }
      if (syncedIds.isNotEmpty) {
        await changeLogRepository.markSynced(syncedIds, syncedAt: nowMs);
      }

      requestBudget.consume(1);
      await remote.updateClientMeta(
        deviceId: deviceId,
        lastSeenLamport: maxLamport,
        lastAppliedChangeId: lastAppliedId,
      );

      state = state.copyWith(
        lastSyncFinishedAt: nowMs,
        lastAppliedChangeId: lastAppliedId,
        lastPushedChangeId: lastPushedId,
        requestWindowStartedAt: requestBudget.windowStartedAt,
        requestCountInWindow: requestBudget.usedCount,
        backoffUntil: null,
        clearError: true,
        updatedAt: nowMs,
      );
      await changeLogRepository.saveSyncState(state);
      _appendLog(
        'INFO',
        '同步完成：pull=${remoteChanges.length}, apply=$appliedCount, push=${syncedIds.length}',
      );
      return SyncRunResult(
        pulledCount: remoteChanges.length,
        appliedCount: appliedCount,
        pushedCount: syncedIds.length,
        skippedByThrottle: false,
        skippedByBackoff: false,
      );
    } on SyncRemoteException catch (error) {
      final int backoffMinutes = _nextBackoffMinutes(
        statusCode: error.statusCode,
        state: state,
      );
      final int? backoffUntil = backoffMinutes <= 0
          ? null
          : nowMs + backoffMinutes * 60 * 1000;
      state = state.copyWith(
        lastSyncFinishedAt: nowMs,
        backoffUntil: backoffUntil,
        lastError: error.message,
        updatedAt: nowMs,
      );
      await changeLogRepository.saveSyncState(state);
      _appendLog('ERROR', '同步失败：${error.message}');
      return SyncRunResult(
        pulledCount: 0,
        appliedCount: 0,
        pushedCount: 0,
        skippedByThrottle: false,
        skippedByBackoff: backoffUntil != null,
        message: error.message,
      );
    } catch (error, stack) {
      _log.warning('同步异常: $error\n$stack');
      state = state.copyWith(
        lastSyncFinishedAt: nowMs,
        lastError: error.toString(),
        updatedAt: nowMs,
      );
      await changeLogRepository.saveSyncState(state);
      _appendLog('ERROR', '同步异常：$error');
      return SyncRunResult(
        pulledCount: 0,
        appliedCount: 0,
        pushedCount: 0,
        skippedByThrottle: false,
        skippedByBackoff: false,
        message: error.toString(),
      );
    }
  }

  int _nextBackoffMinutes({
    required int? statusCode,
    required SyncState state,
  }) {
    if (statusCode == null || (statusCode < 500 && statusCode != 429)) {
      return 0;
    }
    final int currentMinutes = _currentBackoffMinutes(state);
    for (final int minute in SyncConstants.retryBackoffMinutes) {
      if (minute > currentMinutes) {
        return minute;
      }
    }
    return SyncConstants.retryBackoffMinutes.last;
  }

  int _currentBackoffMinutes(SyncState state) {
    if (state.backoffUntil == null || state.lastSyncFinishedAt == null) {
      return 0;
    }
    final int deltaMs = state.backoffUntil! - state.lastSyncFinishedAt!;
    if (deltaMs <= 0) {
      return 0;
    }
    return deltaMs ~/ 60000;
  }

  void _appendLog(String level, String message) {
    _logs.add(
      SyncLogEntry(timestampMs: clock.nowMs(), level: level, message: message),
    );
    while (_logs.length > 300) {
      _logs.removeFirst();
    }
    _log.info('[$level] $message');
  }
}

class _RequestBudgetCounter {
  _RequestBudgetCounter({
    required this.windowStartedAt,
    required this.usedCount,
    required this.limitPerWindow,
    required this.windowMs,
  });

  factory _RequestBudgetCounter.fromState(
    SyncState state, {
    required int nowMs,
    required int limitPerWindow,
    required int windowMs,
  }) {
    final int started = state.requestWindowStartedAt ?? nowMs;
    if (nowMs - started >= windowMs) {
      return _RequestBudgetCounter(
        windowStartedAt: nowMs,
        usedCount: 0,
        limitPerWindow: limitPerWindow,
        windowMs: windowMs,
      );
    }
    return _RequestBudgetCounter(
      windowStartedAt: started,
      usedCount: state.requestCountInWindow,
      limitPerWindow: limitPerWindow,
      windowMs: windowMs,
    );
  }

  final int windowStartedAt;
  final int limitPerWindow;
  final int windowMs;
  int usedCount;

  bool get reachedLimit => usedCount >= limitPerWindow;

  void consume(int count) {
    usedCount += count;
    if (usedCount > limitPerWindow) {
      throw SyncRemoteException(message: '请求预算超限', statusCode: 429);
    }
  }
}

extension<E> on ListQueue<E> {
  Iterable<E> takeLast(int count) sync* {
    if (count <= 0) {
      return;
    }
    final int skip = length > count ? length - count : 0;
    int index = 0;
    for (final E item in this) {
      if (index >= skip) {
        yield item;
      }
      index += 1;
    }
  }
}
