import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/domain/bookmark.dart';
import 'export/export_service.dart';
import 'local/bookmark_repository.dart';
import 'maintenance/maintenance_service.dart';
import 'settings/app_settings.dart';
import 'settings/settings_store.dart';
import 'sync_coordinator.dart';

class AppController extends ChangeNotifier {
  AppController({
    required BookmarkRepository repository,
    required SettingsStore settingsStore,
    required ExportService exportService,
    required MaintenanceService maintenanceService,
    SyncCoordinator? syncCoordinator,
  })  : _repository = repository,
        _settingsStore = settingsStore,
        _exportService = exportService,
        _maintenanceService = maintenanceService,
        _syncCoordinator =
            syncCoordinator ?? SyncCoordinator(repository: repository);

  final BookmarkRepository _repository;
  final SettingsStore _settingsStore;
  final ExportService _exportService;
  final MaintenanceService _maintenanceService;
  final SyncCoordinator _syncCoordinator;
  static const Duration _autoSyncDebounce = Duration(seconds: 12);
  static const Duration _autoSyncMinInterval = Duration(minutes: 3);
  Timer? _refreshTimer;
  Timer? _autoSyncTimer;
  bool _pendingAutoSync = false;
  bool _startupSyncTriggered = false;
  DateTime? _lastAutoSyncStartedAt;

  AppSettings? _settings;
  List<Bookmark> _bookmarks = const <Bookmark>[];
  List<Bookmark> _trashBookmarks = const <Bookmark>[];
  bool _loading = false;
  int _loadingDepth = 0;
  bool _syncing = false;
  bool _backingUp = false;
  DateTime? _lastSyncAt;
  String? _syncError;
  SyncRunDiagnostics? _lastSyncDiagnostics;
  bool _batchRefreshing = false;
  int _batchProcessed = 0;
  int _batchTotal = 0;
  int _batchUpdated = 0;
  String? _error;

  AppSettings get settings {
    final AppSettings? current = _settings;
    if (current == null) {
      throw StateError('AppController 尚未初始化成功');
    }
    return current;
  }

  List<Bookmark> get bookmarks => _bookmarks;
  List<Bookmark> get trashBookmarks => _trashBookmarks;
  bool get loading => _loading;
  bool get syncing => _syncing;
  bool get backingUp => _backingUp;
  DateTime? get lastSyncAt => _lastSyncAt;
  String? get syncError => _syncError;
  SyncRunDiagnostics? get lastSyncDiagnostics => _lastSyncDiagnostics;
  bool get batchRefreshing => _batchRefreshing;
  int get batchProcessed => _batchProcessed;
  int get batchTotal => _batchTotal;
  int get batchUpdated => _batchUpdated;
  double? get batchProgress =>
      _batchTotal <= 0 ? null : _batchProcessed / _batchTotal;
  String? get error => _error;

  Future<void> initialize() async {
    _setLoading(true);
    try {
      _settings = await _settingsStore.load();
      await reloadBookmarks();
      if (_settings!.autoRefreshOnLaunch) {
        await refreshStaleTitles();
      }
      _restartRefreshTimer();
      _error = null;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> reloadBookmarks() async {
    final List<dynamic> results = await Future.wait<dynamic>(<Future<dynamic>>[
      _repository.listBookmarks(),
      _repository.listTrashBookmarks(),
    ]);
    _bookmarks = results[0] as List<Bookmark>;
    _trashBookmarks = results[1] as List<Bookmark>;
    notifyListeners();
  }

  Future<void> addUrl(String input) async {
    _setLoading(true);
    try {
      final Bookmark bookmark = await _repository.addUrl(input);
      await reloadBookmarks();
      await _repository.refreshTitle(bookmark.id);
      await reloadBookmarks();
      _scheduleAutoSync();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> refreshTitle(String bookmarkId) async {
    _setLoading(true);
    try {
      await _repository.refreshTitle(bookmarkId);
      await reloadBookmarks();
      _scheduleAutoSync();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> clearBookmarkNote(String bookmarkId) async {
    _setLoading(true);
    try {
      await _repository.clearNote(bookmarkId);
      await reloadBookmarks();
      _scheduleAutoSync();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<int> refreshStaleTitles() async {
    _setLoading(true);
    _beginBatchRefresh();
    try {
      final int updated = await _repository.refreshTitlesOlderThanWithProgress(
        Duration(days: _settings?.titleRefreshDays ?? 7),
        maxConcurrent: 8,
        onProgress: _onBatchProgress,
      );
      await reloadBookmarks();
      _scheduleAutoSync();
      _error = null;
      return updated;
    } catch (e) {
      _error = e.toString();
      return 0;
    } finally {
      _endBatchRefresh();
      _setLoading(false);
    }
  }

  Future<int> refreshAllTitles() async {
    _setLoading(true);
    _beginBatchRefresh();
    try {
      final int updated = await _repository.refreshAllTitlesWithProgress(
        maxConcurrent: 10,
        onProgress: _onBatchProgress,
      );
      await reloadBookmarks();
      _scheduleAutoSync();
      _error = null;
      return updated;
    } catch (e) {
      _error = e.toString();
      return 0;
    } finally {
      _endBatchRefresh();
      _setLoading(false);
    }
  }

  Future<int> refreshTitlesForBookmarks(List<String> bookmarkIds) async {
    _setLoading(true);
    _beginBatchRefresh();
    try {
      final int updated = await _repository.refreshTitlesByIdsWithProgress(
        bookmarkIds,
        maxConcurrent: 10,
        onProgress: _onBatchProgress,
      );
      await reloadBookmarks();
      _scheduleAutoSync();
      _error = null;
      return updated;
    } catch (e) {
      _error = e.toString();
      return 0;
    } finally {
      _endBatchRefresh();
      _setLoading(false);
    }
  }

  Future<void> deleteBookmark(String bookmarkId) async {
    await deleteBookmarks(<String>[bookmarkId]);
  }

  Future<int> deleteBookmarks(List<String> bookmarkIds) async {
    _setLoading(true);
    try {
      final int affected = await _repository.softDeleteMany(bookmarkIds);
      await reloadBookmarks();
      _scheduleAutoSync();
      _error = null;
      return affected;
    } catch (e) {
      _error = e.toString();
      return 0;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> restoreBookmark(String bookmarkId) async {
    await restoreBookmarks(<String>[bookmarkId]);
  }

  Future<int> restoreBookmarks(List<String> bookmarkIds) async {
    _setLoading(true);
    try {
      final int affected = await _repository.restoreFromTrashMany(bookmarkIds);
      await reloadBookmarks();
      _scheduleAutoSync();
      _error = null;
      return affected;
    } catch (e) {
      _error = e.toString();
      return 0;
    } finally {
      _setLoading(false);
    }
  }

  Future<int> permanentlyDeleteTrash(List<String> bookmarkIds) async {
    _setLoading(true);
    try {
      final int affected = await _repository.permanentlyDeleteFromTrashMany(
        bookmarkIds,
      );
      await reloadBookmarks();
      _error = null;
      return affected;
    } catch (e) {
      _error = e.toString();
      return 0;
    } finally {
      _setLoading(false);
    }
  }

  Future<int> emptyTrash() async {
    _setLoading(true);
    try {
      final int deleted = await _repository.emptyTrash();
      await reloadBookmarks();
      _error = null;
      return deleted;
    } catch (e) {
      _error = e.toString();
      return 0;
    } finally {
      _setLoading(false);
    }
  }

  Future<ExportResult?> exportAll({
    required ExportFormat format,
    required String targetPath,
    bool includeTrash = false,
  }) async {
    _setLoading(true);
    try {
      final List<Bookmark> data = includeTrash
          ? <Bookmark>[..._bookmarks, ..._trashBookmarks]
          : _bookmarks;
      final ExportResult result = await _exportService.exportBookmarks(
        bookmarks: data,
        format: format,
        targetPath: targetPath,
      );
      _error = null;
      return result;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _setLoading(false);
    }
  }

  Future<ExportResult?> exportSelected({
    required List<String> bookmarkIds,
    required bool fromTrash,
    required ExportFormat format,
    required String targetPath,
  }) async {
    _setLoading(true);
    try {
      final Set<String> idSet =
          bookmarkIds.map((String id) => id.trim()).toSet();
      final List<Bookmark> source = fromTrash ? _trashBookmarks : _bookmarks;
      final List<Bookmark> selected =
          source.where((Bookmark b) => idSet.contains(b.id)).toList();
      final ExportResult result = await _exportService.exportBookmarks(
        bookmarks: selected,
        format: format,
        targetPath: targetPath,
      );
      _error = null;
      return result;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _setLoading(false);
    }
  }

  Future<SlimDownResult?> slimDown() async {
    _setLoading(true);
    try {
      final SlimDownResult result = await _maintenanceService.slimDown();
      await reloadBookmarks();
      _error = null;
      return result;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _setLoading(false);
    }
  }

  Future<DedupResult?> deduplicate({
    required bool removeExact,
    required bool removeSimilar,
  }) async {
    _setLoading(true);
    try {
      final DedupResult result = await _repository.deduplicate(
        removeExact: removeExact,
        removeSimilar: removeSimilar,
      );
      await reloadBookmarks();
      _scheduleAutoSync();
      _error = null;
      return result;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> syncNow({bool userInitiated = true}) async {
    return _runSync(userInitiated: userInitiated);
  }

  Future<void> backupNow() async {
    if (_syncing || _backingUp) {
      _error = _syncing ? '正在云同步，请稍后再云备份' : '正在云备份，请稍后重试';
      notifyListeners();
      return;
    }

    _backingUp = true;
    notifyListeners();
    _setLoading(true);
    try {
      await _syncCoordinator.backupNow(settings);
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
      _backingUp = false;
      notifyListeners();
      if (_pendingAutoSync) {
        _pendingAutoSync = false;
        _scheduleAutoSync();
      }
    }
  }

  Future<void> saveSettings(AppSettings next) async {
    _setLoading(true);
    try {
      if (next.webDavEnabled &&
          next.webDavBaseUrl.trim().isNotEmpty &&
          !next.webDavUsesHttps) {
        throw const FormatException('WebDAV Base URL 必须使用 https://');
      }
      await _settingsStore.save(next);
      _settings = next;
      _startupSyncTriggered = false;
      _restartRefreshTimer();
      if (next.autoSyncOnLaunch) {
        unawaited(runStartupSyncIfNeeded());
      }
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> clearAllData() async {
    _setLoading(true);
    try {
      await _repository.clearAllData();
      await _settingsStore.clearAll();
      _settings = await _settingsStore.load();
      await reloadBookmarks();
      _startupSyncTriggered = false;
      _lastSyncAt = null;
      _syncError = null;
      _lastSyncDiagnostics = null;
      _restartRefreshTimer();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> saveHomeSortPreference(HomeSortPreference preference) async {
    final AppSettings? current = _settings;
    if (current == null || current.homeSortPreference == preference) {
      return;
    }

    final AppSettings next = current.copyWith(homeSortPreference: preference);
    _settings = next;
    try {
      await _settingsStore.save(next);
      _error = null;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    if (value) {
      _loadingDepth += 1;
    } else {
      if (_loadingDepth > 0) {
        _loadingDepth -= 1;
      }
    }
    final bool next = _loadingDepth > 0;
    if (_loading == next) {
      return;
    }
    _loading = next;
    notifyListeners();
  }

  void _beginBatchRefresh() {
    _batchRefreshing = true;
    _batchProcessed = 0;
    _batchTotal = 0;
    _batchUpdated = 0;
    notifyListeners();
  }

  void _onBatchProgress(int processed, int total, int updated) {
    _batchProcessed = processed;
    _batchTotal = total;
    _batchUpdated = updated;
    notifyListeners();
  }

  void _endBatchRefresh() {
    _batchRefreshing = false;
    notifyListeners();
  }

  void _restartRefreshTimer() {
    _refreshTimer?.cancel();
    final AppSettings? current = _settings;
    if (current == null || !current.autoRefreshOnLaunch) {
      return;
    }

    _refreshTimer = Timer.periodic(const Duration(hours: 6), (_) {
      if (!_loading) {
        refreshStaleTitles();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _autoSyncTimer?.cancel();
    _repository.dispose();
    super.dispose();
  }

  Future<bool> runStartupSyncIfNeeded() async {
    if (_startupSyncTriggered) return false;
    _startupSyncTriggered = true;

    final AppSettings? current = _settings;
    if (current == null || !current.syncReady || !current.autoSyncOnLaunch) {
      return false;
    }

    final bool syncSuccess = await _runSync(userInitiated: false);
    if (!syncSuccess) {
      return false;
    }

    try {
      final String markdown = _exportService.buildMarkdownContent(_bookmarks);
      await _syncCoordinator.backupMarkdownNow(
        settings: current,
        markdown: markdown,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Startup markdown backup failed: $e');
      }
    }

    return syncSuccess;
  }

  void _scheduleAutoSync() {
    final AppSettings? current = _settings;
    if (current == null || !current.syncReady || !current.autoSyncOnChange) {
      return;
    }
    if (_syncing || _backingUp) {
      _pendingAutoSync = true;
      return;
    }
    final DateTime now = DateTime.now();
    final Duration delay = _calculateAutoSyncDelay(now);
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer(delay, () {
      unawaited(_runSync(userInitiated: false, autoScheduled: true));
    });
  }

  Duration _calculateAutoSyncDelay(DateTime now) {
    final DateTime? last = _lastAutoSyncStartedAt;
    if (last == null) {
      return _autoSyncDebounce;
    }
    final DateTime cooldownEndsAt = last.add(_autoSyncMinInterval);
    if (cooldownEndsAt.isAfter(now)) {
      final Duration cooldown = cooldownEndsAt.difference(now);
      return cooldown > _autoSyncDebounce ? cooldown : _autoSyncDebounce;
    }
    return _autoSyncDebounce;
  }

  Future<bool> _runSync({
    required bool userInitiated,
    bool autoScheduled = false,
  }) async {
    final AppSettings? current = _settings;
    if (current == null || !current.syncReady) {
      return false;
    }

    if (_syncing) {
      if (autoScheduled) {
        _pendingAutoSync = true;
      }
      return false;
    }
    if (_backingUp) {
      if (autoScheduled) {
        _pendingAutoSync = true;
      }
      if (userInitiated) {
        _error = '正在云备份，请稍后再云同步';
        notifyListeners();
      }
      return false;
    }

    if (autoScheduled) {
      _lastAutoSyncStartedAt = DateTime.now();
    }
    _syncing = true;
    notifyListeners();
    bool success = false;
    try {
      final SyncRunDiagnostics report = await _syncCoordinator.syncNow(current);
      _lastSyncDiagnostics = report;
      if (report.success) {
        await reloadBookmarks();
        _lastSyncAt = report.finishedAt;
        _syncError = null;
        _error = null;
        success = true;
      } else {
        final String message = report.errorMessage ?? '同步失败';
        _syncError = message;
        if (userInitiated) {
          _error = message;
        }
        success = false;
      }
    } catch (e) {
      _syncError = e.toString();
      _lastSyncDiagnostics = SyncRunDiagnostics(
        startedAt: DateTime.now(),
        finishedAt: DateTime.now(),
        attemptCount: 1,
        success: false,
        engineReport: null,
        errorMessage: e.toString(),
      );
      if (userInitiated) {
        _error = e.toString();
      }
      success = false;
    } finally {
      _syncing = false;
      notifyListeners();
    }

    if (_pendingAutoSync) {
      _pendingAutoSync = false;
      _scheduleAutoSync();
    }

    return success;
  }
}
