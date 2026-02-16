import 'local/bookmark_repository.dart';
import 'settings/app_settings.dart';
import '../core/backup/webdav_backup_service.dart';
import '../core/domain/bookmark.dart';
import '../core/sync/sync_engine.dart';
import '../core/sync/webdav_sync_provider.dart';

class SyncCoordinator {
  SyncCoordinator({required BookmarkRepository repository})
    : _repository = repository;

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

    await engine.syncOnce();
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

    await backupService.uploadSnapshot(
      userId: settings.webDavUserId,
      bookmarks: bookmarks,
    );
  }

  void _assertSyncReady(AppSettings settings) {
    if (!settings.syncReady) {
      throw StateError('请先在设置页配置 WebDAV 信息');
    }
  }

  String _normalizeBaseUrl(String input) {
    final String trimmed = input.trim();
    if (trimmed.isEmpty) return trimmed;
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}
