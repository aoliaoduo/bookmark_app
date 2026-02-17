import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'local/bookmark_repository.dart';
import 'settings/app_settings.dart';
import '../core/backup/webdav_backup_service.dart';
import '../core/domain/bookmark.dart';
import '../core/sync/sync_engine.dart';
import '../core/sync/webdav_sync_provider.dart';

class SyncCoordinator {
  SyncCoordinator({required BookmarkRepository repository})
      : _repository = repository;

  static const int _maxAttempts = 3;
  static const List<Duration> _retryDelay = <Duration>[
    Duration(milliseconds: 800),
    Duration(milliseconds: 1800),
  ];

  final BookmarkRepository _repository;

  Future<void> syncNow(AppSettings settings) async {
    _assertSyncReady(settings);

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

    await _runWithRetry(engine.syncOnce);
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

    await _runWithRetry(() {
      return backupService.uploadSnapshot(
        userId: settings.webDavUserId,
        bookmarks: bookmarks,
      );
    });
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

  Future<void> _runWithRetry(Future<void> Function() task) async {
    Object? lastError;
    StackTrace? lastStack;

    for (int attempt = 1; attempt <= _maxAttempts; attempt += 1) {
      try {
        await task();
        return;
      } catch (error, stack) {
        lastError = error;
        lastStack = stack;
        if (!_isTransientError(error) || attempt >= _maxAttempts) {
          rethrow;
        }
        await Future<void>.delayed(_retryDelay[attempt - 1]);
      }
    }

    Error.throwWithStackTrace(lastError!, lastStack!);
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
}
