import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'local/bookmark_repository.dart';
import 'settings/app_settings.dart';
import '../core/backup/webdav_backup_service.dart';
import '../core/domain/bookmark.dart';
import '../core/sync/sync_engine.dart';
import '../core/sync/webdav_sync_provider.dart';

class SyncRunDiagnostics {
  const SyncRunDiagnostics({
    required this.startedAt,
    required this.finishedAt,
    required this.attemptCount,
    required this.success,
    required this.engineReport,
    this.errorMessage,
  });

  final DateTime startedAt;
  final DateTime finishedAt;
  final int attemptCount;
  final bool success;
  final SyncEngineReport? engineReport;
  final String? errorMessage;

  Duration get duration => finishedAt.difference(startedAt);
  int get retryCount => attemptCount <= 1 ? 0 : attemptCount - 1;

  int get localPendingOps => engineReport?.localPendingOps ?? 0;
  int get pushedOps => engineReport?.pushedOps ?? 0;
  int get pulledBatchCount => engineReport?.pulledBatchCount ?? 0;
  int get pulledOps => engineReport?.pulledOps ?? 0;
  int get filteredDuplicateOrSelfOps =>
      engineReport?.filteredDuplicateOrSelfOps ?? 0;
  int get filteredStaleOps => engineReport?.filteredStaleOps ?? 0;
  int get appliedUpserts => engineReport?.appliedUpserts ?? 0;
  int get appliedDeletes => engineReport?.appliedDeletes ?? 0;
}

class SyncCoordinator {
  SyncCoordinator({required BookmarkRepository repository})
      : _repository = repository;

  static const int _maxAttempts = 3;
  static const List<Duration> _retryDelay = <Duration>[
    Duration(milliseconds: 800),
    Duration(milliseconds: 1800),
  ];

  final BookmarkRepository _repository;

  Future<SyncRunDiagnostics> syncNow(AppSettings settings) async {
    _assertSyncReady(settings);
    final DateTime startedAt = DateTime.now();

    final WebDavConfig config = WebDavConfig(
      baseUrl: _normalizeBaseUrl(settings.webDavBaseUrl),
      username: settings.webDavUsername,
      password: settings.webDavPassword,
    );

    final SyncEngine engine = SyncEngine(
      localStore: _repository,
      syncProvider: WebDavSyncProvider(config: config),
      userId: settings.webDavUserId,
      deviceId: settings.deviceId,
    );

    final _RetryOutcome<SyncEngineReport> outcome = await _runWithRetry(
      engine.syncOnce,
    );
    final DateTime finishedAt = DateTime.now();
    if (outcome.value != null) {
      return SyncRunDiagnostics(
        startedAt: startedAt,
        finishedAt: finishedAt,
        attemptCount: outcome.attemptCount,
        success: true,
        engineReport: outcome.value,
      );
    }
    return SyncRunDiagnostics(
      startedAt: startedAt,
      finishedAt: finishedAt,
      attemptCount: outcome.attemptCount,
      success: false,
      engineReport: null,
      errorMessage: outcome.error?.toString(),
    );
  }

  Future<void> backupNow(AppSettings settings) async {
    _assertSyncReady(settings);

    final List<Bookmark> bookmarks = await _repository.listBookmarks(
      includeDeleted: true,
    );

    final WebDavBackupService backupService = WebDavBackupService(
      config: WebDavConfig(
        baseUrl: _normalizeBaseUrl(settings.webDavBaseUrl),
        username: settings.webDavUsername,
        password: settings.webDavPassword,
      ),
    );

    final _RetryOutcome<void> outcome = await _runWithRetry(() {
      return backupService.uploadSnapshot(
        userId: settings.webDavUserId,
        bookmarks: bookmarks,
      );
    });
    if (outcome.error != null) {
      _throwWithStack(outcome.error!, outcome.stackTrace);
    }
  }

  void _assertSyncReady(AppSettings settings) {
    if (!settings.syncReady) {
      throw StateError('请先在设置页配置 WebDAV 信息');
    }
  }

  String _normalizeBaseUrl(String input) {
    final String trimmed = input.trim();
    if (trimmed.isEmpty) return trimmed;
    final String noTrailingSlash = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    final Uri? parsed = Uri.tryParse(noTrailingSlash);
    if (parsed == null || !parsed.hasScheme || !parsed.hasAuthority) {
      return noTrailingSlash;
    }

    final String marker = '/bookmarksapp';
    final String lowerPath = parsed.path.toLowerCase();
    final int markerIndex = lowerPath.indexOf(marker);
    final String normalizedPath =
        markerIndex >= 0 ? parsed.path.substring(0, markerIndex) : parsed.path;

    return parsed.replace(path: normalizedPath).toString().replaceFirst(
          RegExp(r'/$'),
          '',
        );
  }

  Future<_RetryOutcome<T>> _runWithRetry<T>(Future<T> Function() task) async {
    Object? lastError;
    StackTrace? lastStack;

    for (int attempt = 1; attempt <= _maxAttempts; attempt += 1) {
      try {
        final T value = await task();
        return _RetryOutcome<T>(
          value: value,
          attemptCount: attempt,
        );
      } catch (error, stack) {
        lastError = error;
        lastStack = stack;
        if (!_isTransientError(error) || attempt >= _maxAttempts) {
          return _RetryOutcome<T>(
            error: lastError,
            stackTrace: lastStack,
            attemptCount: attempt,
          );
        }
        await Future<void>.delayed(_retryDelay[attempt - 1]);
      }
    }

    return _RetryOutcome<T>(
      error: lastError,
      stackTrace: lastStack,
      attemptCount: _maxAttempts,
    );
  }

  bool _isTransientError(Object error) {
    if (error is TimeoutException ||
        error is SocketException ||
        error is HttpException ||
        error is HandshakeException ||
        error is http.ClientException) {
      return true;
    }

    if (error is WebDavRequestException) {
      final int? code = error.statusCode;
      if (code == null) {
        return true;
      }
      return code == 408 || code == 429 || code >= 500;
    }

    final String msg = error.toString().toLowerCase();
    return msg.contains('timed out') ||
        msg.contains('failed host lookup') ||
        msg.contains('connection refused') ||
        msg.contains('connection reset') ||
        msg.contains('network is unreachable') ||
        msg.contains('temporarily unavailable');
  }

  Never _throwWithStack(Object error, StackTrace? stack) {
    if (stack != null) {
      Error.throwWithStackTrace(error, stack);
    }
    throw error;
  }
}

class _RetryOutcome<T> {
  const _RetryOutcome({
    this.value,
    this.error,
    this.stackTrace,
    required this.attemptCount,
  });

  final T? value;
  final Object? error;
  final StackTrace? stackTrace;
  final int attemptCount;
}
