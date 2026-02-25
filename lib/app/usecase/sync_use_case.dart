import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../settings/app_settings.dart';
import '../sync_coordinator.dart';

enum SyncJobKind {
  sync,
  backupSnapshot,
  backupMarkdown,
}

class SyncTaskCanceledException implements Exception {
  const SyncTaskCanceledException([this.message = '同步任务已取消']);

  final String message;

  @override
  String toString() => message;
}

class SyncTaskHandle<T> {
  const SyncTaskHandle._({
    required this.id,
    required this.kind,
    required this.result,
    required bool Function() cancel,
  }) : _cancel = cancel;

  final int id;
  final SyncJobKind kind;
  final Future<T> result;
  final bool Function() _cancel;

  bool cancel() => _cancel();
}

abstract class SyncGateway {
  Future<SyncRunDiagnostics> syncNow(AppSettings settings);
  Future<void> backupNow(AppSettings settings);
  Future<void> backupMarkdownNow({
    required AppSettings settings,
    required String markdown,
  });
}

class SyncCoordinatorGateway implements SyncGateway {
  SyncCoordinatorGateway(this._coordinator);

  final SyncCoordinator _coordinator;

  @override
  Future<SyncRunDiagnostics> syncNow(AppSettings settings) {
    return _coordinator.syncNow(settings);
  }

  @override
  Future<void> backupNow(AppSettings settings) {
    return _coordinator.backupNow(settings);
  }

  @override
  Future<void> backupMarkdownNow({
    required AppSettings settings,
    required String markdown,
  }) {
    return _coordinator.backupMarkdownNow(
      settings: settings,
      markdown: markdown,
    );
  }
}

class SyncUseCase extends ChangeNotifier {
  SyncUseCase({required SyncGateway gateway}) : _gateway = gateway;

  final SyncGateway _gateway;
  final Queue<_QueuedSyncJob<dynamic>> _queue =
      Queue<_QueuedSyncJob<dynamic>>();
  _QueuedSyncJob<dynamic>? _activeJob;
  int _nextJobId = 1;

  SyncJobKind? get runningJobKind => _activeJob?.kind;
  bool get isSyncing => runningJobKind == SyncJobKind.sync;
  bool get isBackingUp {
    final SyncJobKind? kind = runningJobKind;
    return kind == SyncJobKind.backupSnapshot ||
        kind == SyncJobKind.backupMarkdown;
  }

  int get queuedJobCount => _queue.where((job) => !job.canceled).length;

  SyncTaskHandle<SyncRunDiagnostics> enqueueSync({
    required AppSettings settings,
    String? queueTag,
  }) {
    return _enqueue<SyncRunDiagnostics>(
      kind: SyncJobKind.sync,
      queueTag: queueTag,
      run: () => _gateway.syncNow(settings),
    );
  }

  SyncTaskHandle<void> enqueueBackupSnapshot({
    required AppSettings settings,
    String? queueTag,
  }) {
    return _enqueue<void>(
      kind: SyncJobKind.backupSnapshot,
      queueTag: queueTag,
      run: () => _gateway.backupNow(settings),
    );
  }

  SyncTaskHandle<void> enqueueBackupMarkdown({
    required AppSettings settings,
    required String markdown,
    String? queueTag,
  }) {
    return _enqueue<void>(
      kind: SyncJobKind.backupMarkdown,
      queueTag: queueTag,
      run: () => _gateway.backupMarkdownNow(
        settings: settings,
        markdown: markdown,
      ),
    );
  }

  int cancelQueued({SyncJobKind? kind, String? queueTag}) {
    int canceled = 0;
    for (final _QueuedSyncJob<dynamic> job in _queue) {
      if (job.started || job.canceled) {
        continue;
      }
      if (kind != null && job.kind != kind) {
        continue;
      }
      if (queueTag != null && job.queueTag != queueTag) {
        continue;
      }
      job.canceled = true;
      if (!job.completer.isCompleted) {
        job.completer.completeError(const SyncTaskCanceledException());
      }
      canceled += 1;
    }
    if (canceled > 0) {
      notifyListeners();
    }
    return canceled;
  }

  @override
  void dispose() {
    cancelQueued();
    super.dispose();
  }

  SyncTaskHandle<T> _enqueue<T>({
    required SyncJobKind kind,
    required Future<T> Function() run,
    String? queueTag,
  }) {
    final _QueuedSyncJob<dynamic>? existing =
        _findExisting(kind: kind, queueTag: queueTag);
    if (existing != null) {
      return existing.handle as SyncTaskHandle<T>;
    }

    final int jobId = _nextJobId;
    _nextJobId += 1;
    final Completer<T> completer = Completer<T>();
    late final _QueuedSyncJob<T> job;
    final SyncTaskHandle<T> handle = SyncTaskHandle<T>._(
      id: jobId,
      kind: kind,
      result: completer.future,
      cancel: () => _cancelJob(job),
    );
    job = _QueuedSyncJob<T>(
      id: jobId,
      kind: kind,
      queueTag: queueTag,
      run: run,
      completer: completer,
      handle: handle,
    );
    _queue.addLast(job);
    notifyListeners();
    _pump();
    return handle;
  }

  _QueuedSyncJob<dynamic>? _findExisting({
    required SyncJobKind kind,
    required String? queueTag,
  }) {
    if (queueTag == null || queueTag.trim().isEmpty) {
      return null;
    }
    final String targetTag = queueTag.trim();

    final _QueuedSyncJob<dynamic>? active = _activeJob;
    if (active != null &&
        !active.canceled &&
        active.kind == kind &&
        active.queueTag == targetTag) {
      return active;
    }

    for (final _QueuedSyncJob<dynamic> queued in _queue) {
      if (queued.canceled || queued.kind != kind) {
        continue;
      }
      if (queued.queueTag == targetTag) {
        return queued;
      }
    }
    return null;
  }

  bool _cancelJob<T>(_QueuedSyncJob<T> job) {
    if (job.started || job.canceled) {
      return false;
    }
    job.canceled = true;
    if (!job.completer.isCompleted) {
      job.completer.completeError(const SyncTaskCanceledException());
    }
    notifyListeners();
    return true;
  }

  void _pump() {
    if (_activeJob != null) {
      return;
    }

    while (_queue.isNotEmpty) {
      final _QueuedSyncJob<dynamic> next = _queue.removeFirst();
      if (next.canceled) {
        continue;
      }
      _activeJob = next;
      next.started = true;
      notifyListeners();
      unawaited(_runJob(next));
      return;
    }
  }

  Future<void> _runJob(_QueuedSyncJob<dynamic> job) async {
    try {
      final dynamic value = await job.run();
      if (!job.completer.isCompleted) {
        job.completer.complete(value);
      }
    } catch (e, st) {
      if (!job.completer.isCompleted) {
        job.completer.completeError(e, st);
      }
    } finally {
      if (identical(_activeJob, job)) {
        _activeJob = null;
      }
      notifyListeners();
      _pump();
    }
  }
}

class _QueuedSyncJob<T> {
  _QueuedSyncJob({
    required this.id,
    required this.kind,
    required this.queueTag,
    required this.run,
    required this.completer,
    required this.handle,
  });

  final int id;
  final SyncJobKind kind;
  final String? queueTag;
  final Future<T> Function() run;
  final Completer<T> completer;
  final SyncTaskHandle<T> handle;
  bool started = false;
  bool canceled = false;
}
