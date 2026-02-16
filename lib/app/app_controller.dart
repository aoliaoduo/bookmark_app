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
  })  : _repository = repository,
        _settingsStore = settingsStore,
        _exportService = exportService,
        _maintenanceService = maintenanceService,
        _syncCoordinator = SyncCoordinator(repository: repository);

  final BookmarkRepository _repository;
  final SettingsStore _settingsStore;
  final ExportService _exportService;
  final MaintenanceService _maintenanceService;
  final SyncCoordinator _syncCoordinator;
  Timer? _refreshTimer;

  AppSettings? _settings;
  List<Bookmark> _bookmarks = const <Bookmark>[];
  List<Bookmark> _trashBookmarks = const <Bookmark>[];
  bool _loading = false;
  bool _batchRefreshing = false;
  int _batchProcessed = 0;
  int _batchTotal = 0;
  int _batchUpdated = 0;
  String? _error;

  AppSettings get settings => _settings!;
  List<Bookmark> get bookmarks => _bookmarks;
  List<Bookmark> get trashBookmarks => _trashBookmarks;
  bool get loading => _loading;
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
    } catch (e) {
      _error = e.toString();
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
      _error = null;
      return result;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> syncNow() async {
    _setLoading(true);
    try {
      await _syncCoordinator.syncNow(settings);
      await reloadBookmarks();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> backupNow() async {
    _setLoading(true);
    try {
      await _syncCoordinator.backupNow(settings);
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> saveSettings(AppSettings next) async {
    _setLoading(true);
    try {
      await _settingsStore.save(next);
      _settings = next;
      _restartRefreshTimer();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _loading = value;
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
    super.dispose();
  }
}
