import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/domain/bookmark.dart';
import '../core/security/sensitive_data_sanitizer.dart';
import 'export/export_service.dart';
import 'local/bookmark_repository.dart';
import 'maintenance/maintenance_service.dart';
import 'settings/app_settings.dart';
import 'settings/settings_store.dart';
import 'sync_coordinator.dart';
import 'usecase/bookmark_use_case.dart';
import 'usecase/maintenance_use_case.dart';
import 'usecase/sync_use_case.dart';

enum AppBootstrapState {
  booting,
  ready,
  degraded,
  failed,
}

class AppController extends ChangeNotifier {
  AppController({
    required BookmarkRepository repository,
    required SettingsStore settingsStore,
    required ExportService exportService,
    required MaintenanceService maintenanceService,
    SyncCoordinator? syncCoordinator,
    BookmarkUseCase? bookmarkUseCase,
    SyncUseCase? syncUseCase,
    MaintenanceUseCase? maintenanceUseCase,
  })  : _settingsStore = settingsStore,
        _bookmarkUseCase = bookmarkUseCase ??
            BookmarkUseCase(
              repository: repository,
              exportService: exportService,
            ),
        _syncUseCase = syncUseCase ??
            SyncUseCase(
              gateway: SyncCoordinatorGateway(
                syncCoordinator ?? SyncCoordinator(repository: repository),
              ),
            ),
        _maintenanceUseCase = maintenanceUseCase ??
            MaintenanceUseCase(
              repository: repository,
              maintenanceService: maintenanceService,
            ),
        _ownsBookmarkUseCase = bookmarkUseCase == null,
        _ownsSyncUseCase = syncUseCase == null {
    _syncing = _syncUseCase.isSyncing;
    _backingUp = _syncUseCase.isBackingUp;
    _syncUseCase.addListener(_onSyncUseCaseChanged);
  }

  final SettingsStore _settingsStore;
  final BookmarkUseCase _bookmarkUseCase;
  final SyncUseCase _syncUseCase;
  final MaintenanceUseCase _maintenanceUseCase;
  final bool _ownsBookmarkUseCase;
  final bool _ownsSyncUseCase;

  static const Duration _autoSyncDebounce = Duration(seconds: 12);
  static const Duration _autoSyncMinInterval = Duration(minutes: 3);
  static const String _autoSyncQueueTag = 'auto-sync';

  Timer? _refreshTimer;
  Timer? _autoSyncTimer;
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

  AppBootstrapState _bootstrapState = AppBootstrapState.booting;
  String? _bootstrapMessage;

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
  AppBootstrapState get bootstrapState => _bootstrapState;
  String? get bootstrapMessage => _bootstrapMessage;

  Future<void> initialize() async {
    _setBootstrapState(AppBootstrapState.booting);
    _setLoading(true);
    try {
      _settings = await _settingsStore.load();
      await reloadBookmarks();
      _restartRefreshTimer();

      String? degradedMessage;
      if (_settings!.autoRefreshOnLaunch) {
        await refreshStaleTitles();
        final String? currentError = _error;
        if (currentError != null && currentError.trim().isNotEmpty) {
          degradedMessage = currentError;
        }
      }

      if (degradedMessage != null) {
        _setBootstrapState(
          AppBootstrapState.degraded,
          message: degradedMessage,
        );
      } else {
        _setBootstrapState(AppBootstrapState.ready);
        _error = null;
      }
    } catch (e) {
      _settings = null;
      _error = _safeErrorMessage(e);
      _setBootstrapState(AppBootstrapState.failed, message: _error);
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> reloadBookmarks() async {
    final BookmarkLoadResult result =
        await _bookmarkUseCase.loadBookmarkLists();
    _bookmarks = result.bookmarks;
    _trashBookmarks = result.trashBookmarks;
    notifyListeners();
  }

  Future<void> addUrl(String input) async {
    _setLoading(true);
    try {
      final Bookmark bookmark = await _bookmarkUseCase.addUrl(input);
      await reloadBookmarks();
      await _bookmarkUseCase.refreshTitle(bookmark.id);
      await reloadBookmarks();
      _scheduleAutoSync();
      _error = null;
    } catch (e) {
      _error = _safeErrorMessage(e);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> refreshTitle(String bookmarkId) async {
    _setLoading(true);
    try {
      await _bookmarkUseCase.refreshTitle(bookmarkId);
      await reloadBookmarks();
      _scheduleAutoSync();
      _error = null;
    } catch (e) {
      _error = _safeErrorMessage(e);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> clearBookmarkNote(String bookmarkId) async {
    _setLoading(true);
    try {
      await _bookmarkUseCase.clearBookmarkNote(bookmarkId);
      await reloadBookmarks();
      _scheduleAutoSync();
      _error = null;
    } catch (e) {
      _error = _safeErrorMessage(e);
    } finally {
      _setLoading(false);
    }
  }

  Future<int> refreshStaleTitles() async {
    _setLoading(true);
    _beginBatchRefresh();
    try {
      final int updated = await _bookmarkUseCase.refreshStaleTitles(
        refreshDays: _settings?.titleRefreshDays ?? 7,
        maxConcurrent: 8,
        onProgress: _onBatchProgress,
      );
      await reloadBookmarks();
      _scheduleAutoSync();
      _error = null;
      return updated;
    } catch (e) {
      _error = _safeErrorMessage(e);
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
      final int updated = await _bookmarkUseCase.refreshAllTitles(
        maxConcurrent: 10,
        onProgress: _onBatchProgress,
      );
      await reloadBookmarks();
      _scheduleAutoSync();
      _error = null;
      return updated;
    } catch (e) {
      _error = _safeErrorMessage(e);
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
      final int updated = await _bookmarkUseCase.refreshTitlesForBookmarks(
        bookmarkIds,
        maxConcurrent: 10,
        onProgress: _onBatchProgress,
      );
      await reloadBookmarks();
      _scheduleAutoSync();
      _error = null;
      return updated;
    } catch (e) {
      _error = _safeErrorMessage(e);
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
      final int affected = await _bookmarkUseCase.deleteBookmarks(bookmarkIds);
      await reloadBookmarks();
      _scheduleAutoSync();
      _error = null;
      return affected;
    } catch (e) {
      _error = _safeErrorMessage(e);
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
      final int affected = await _bookmarkUseCase.restoreBookmarks(bookmarkIds);
      await reloadBookmarks();
      _scheduleAutoSync();
      _error = null;
      return affected;
    } catch (e) {
      _error = _safeErrorMessage(e);
      return 0;
    } finally {
      _setLoading(false);
    }
  }

  Future<int> permanentlyDeleteTrash(List<String> bookmarkIds) async {
    _setLoading(true);
    try {
      final int affected = await _bookmarkUseCase.permanentlyDeleteTrash(
        bookmarkIds,
      );
      await reloadBookmarks();
      _error = null;
      return affected;
    } catch (e) {
      _error = _safeErrorMessage(e);
      return 0;
    } finally {
      _setLoading(false);
    }
  }

  Future<int> emptyTrash() async {
    _setLoading(true);
    try {
      final int deleted = await _bookmarkUseCase.emptyTrash();
      await reloadBookmarks();
      _error = null;
      return deleted;
    } catch (e) {
      _error = _safeErrorMessage(e);
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
      final ExportResult result = await _bookmarkUseCase.exportAll(
        format: format,
        targetPath: targetPath,
        includeTrash: includeTrash,
      );
      _error = null;
      return result;
    } catch (e) {
      _error = _safeErrorMessage(e);
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
      final ExportResult result = await _bookmarkUseCase.exportSelected(
        bookmarkIds: bookmarkIds,
        fromTrash: fromTrash,
        format: format,
        targetPath: targetPath,
      );
      _error = null;
      return result;
    } catch (e) {
      _error = _safeErrorMessage(e);
      return null;
    } finally {
      _setLoading(false);
    }
  }

  Future<SlimDownResult?> slimDown() async {
    _setLoading(true);
    try {
      final SlimDownResult result = await _maintenanceUseCase.slimDown();
      await reloadBookmarks();
      _error = null;
      return result;
    } catch (e) {
      _error = _safeErrorMessage(e);
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
      final DedupResult result = await _maintenanceUseCase.deduplicate(
        removeExact: removeExact,
        removeSimilar: removeSimilar,
      );
      await reloadBookmarks();
      _scheduleAutoSync();
      _error = null;
      return result;
    } catch (e) {
      _error = _safeErrorMessage(e);
      return null;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> syncNow({bool userInitiated = true}) async {
    return _runSync(userInitiated: userInitiated);
  }

  Future<void> backupNow() async {
    final AppSettings? current = _settings;
    if (current == null || !current.syncReady) {
      _error = '璇峰厛鍦ㄨ缃腑瀹屾垚 WebDAV 閰嶇疆';
      notifyListeners();
      return;
    }

    _setLoading(true);
    try {
      final SyncTaskHandle<void> handle = _syncUseCase.enqueueBackupSnapshot(
        settings: current,
      );
      await handle.result;
      _error = null;
    } on SyncTaskCanceledException {
      if (kDebugMode) {
        debugPrint('Backup task canceled before execution');
      }
    } catch (e) {
      _error = _safeErrorMessage(e);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> saveSettings(AppSettings next) async {
    _setLoading(true);
    try {
      if (next.webDavEnabled &&
          next.webDavBaseUrl.trim().isNotEmpty &&
          !next.webDavUsesHttps) {
        throw const FormatException('WebDAV Base URL 蹇呴』浣跨敤 https://');
      }
      await _settingsStore.save(next);
      _settings = next;
      _startupSyncTriggered = false;
      _restartRefreshTimer();
      if (!next.syncReady || !next.autoSyncOnChange) {
        _cancelAutoSyncScheduling();
      }
      if (next.autoSyncOnLaunch) {
        unawaited(runStartupSyncIfNeeded());
      }
      _error = null;
    } catch (e) {
      _error = _safeErrorMessage(e);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> clearAllData() async {
    _setLoading(true);
    try {
      _cancelAutoSyncScheduling();
      _syncUseCase.cancelQueued();
      await _bookmarkUseCase.clearAllData();
      await _settingsStore.clearAll();
      _settings = await _settingsStore.load();
      await reloadBookmarks();
      _startupSyncTriggered = false;
      _lastSyncAt = null;
      _syncError = null;
      _lastSyncDiagnostics = null;
      _setBootstrapState(AppBootstrapState.ready);
      _restartRefreshTimer();
      _error = null;
    } catch (e) {
      _error = _safeErrorMessage(e);
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
      _error = _safeErrorMessage(e);
      notifyListeners();
    }
  }

  int cancelQueuedSyncJobs({SyncJobKind? kind, String? queueTag}) {
    return _syncUseCase.cancelQueued(kind: kind, queueTag: queueTag);
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
        unawaited(refreshStaleTitles());
      }
    });
  }

  void _cancelAutoSyncScheduling() {
    _autoSyncTimer?.cancel();
    _syncUseCase.cancelQueued(
      kind: SyncJobKind.sync,
      queueTag: _autoSyncQueueTag,
    );
  }

  void _onSyncUseCaseChanged() {
    final bool nextSyncing = _syncUseCase.isSyncing;
    final bool nextBackingUp = _syncUseCase.isBackingUp;
    if (_syncing == nextSyncing && _backingUp == nextBackingUp) {
      return;
    }
    _syncing = nextSyncing;
    _backingUp = nextBackingUp;
    notifyListeners();
  }

  void _setBootstrapState(AppBootstrapState next, {String? message}) {
    if (_bootstrapState == next && _bootstrapMessage == message) {
      return;
    }
    _bootstrapState = next;
    _bootstrapMessage = message;
    notifyListeners();
  }

  String _safeErrorMessage(Object error) {
    return SensitiveDataSanitizer.sanitizeObject(error);
  }

  String _safeErrorText(String message) {
    return SensitiveDataSanitizer.sanitizeText(message);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _autoSyncTimer?.cancel();
    _syncUseCase.removeListener(_onSyncUseCaseChanged);
    if (_ownsSyncUseCase) {
      _syncUseCase.dispose();
    }
    if (_ownsBookmarkUseCase) {
      _bookmarkUseCase.dispose();
    }
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
      final String markdown = _bookmarkUseCase.buildMarkdownContent(_bookmarks);
      final SyncTaskHandle<void> handle = _syncUseCase.enqueueBackupMarkdown(
        settings: current,
        markdown: markdown,
      );
      await handle.result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'Startup markdown backup failed: ${_safeErrorMessage(e)}',
        );
      }
    }

    return syncSuccess;
  }

  void _scheduleAutoSync() {
    final AppSettings? current = _settings;
    if (current == null || !current.syncReady || !current.autoSyncOnChange) {
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

    if (autoScheduled) {
      _lastAutoSyncStartedAt = DateTime.now();
    }

    try {
      final SyncTaskHandle<SyncRunDiagnostics> handle =
          _syncUseCase.enqueueSync(
        settings: current,
        queueTag: autoScheduled ? _autoSyncQueueTag : null,
      );
      final SyncRunDiagnostics report = await handle.result;
      _lastSyncDiagnostics = report;
      if (report.success) {
        await reloadBookmarks();
        _lastSyncAt = report.finishedAt;
        _syncError = null;
        _error = null;
        return true;
      }
      final String message = _safeErrorText(
        report.errorMessage ?? '同步失败',
      );
      _syncError = message;
      if (userInitiated) {
        _error = message;
      }
      return false;
    } on SyncTaskCanceledException {
      return false;
    } catch (e) {
      _syncError = _safeErrorMessage(e);
      _lastSyncDiagnostics = SyncRunDiagnostics(
        startedAt: DateTime.now(),
        finishedAt: DateTime.now(),
        attemptCount: 1,
        success: false,
        engineReport: null,
        errorMessage: _safeErrorMessage(e),
      );
      if (userInitiated) {
        _error = _safeErrorMessage(e);
      }
      return false;
    }
  }
}
