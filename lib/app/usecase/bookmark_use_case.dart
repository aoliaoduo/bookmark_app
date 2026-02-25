import '../../core/domain/bookmark.dart';
import '../export/export_service.dart';
import '../local/bookmark_repository.dart';

typedef BookmarkProgressCallback = void Function(
  int processed,
  int total,
  int updated,
);

class BookmarkLoadResult {
  const BookmarkLoadResult({
    required this.bookmarks,
    required this.trashBookmarks,
  });

  final List<Bookmark> bookmarks;
  final List<Bookmark> trashBookmarks;
}

class BookmarkUseCase {
  BookmarkUseCase({
    required BookmarkRepository repository,
    required ExportService exportService,
  })  : _repository = repository,
        _exportService = exportService;

  final BookmarkRepository _repository;
  final ExportService _exportService;

  Future<BookmarkLoadResult> loadBookmarkLists() async {
    final List<dynamic> results = await Future.wait<dynamic>(<Future<dynamic>>[
      _repository.listBookmarks(),
      _repository.listTrashBookmarks(),
    ]);
    return BookmarkLoadResult(
      bookmarks: results[0] as List<Bookmark>,
      trashBookmarks: results[1] as List<Bookmark>,
    );
  }

  Future<Bookmark> addUrl(String input) {
    return _repository.addUrl(input);
  }

  Future<Bookmark?> refreshTitle(String bookmarkId) {
    return _repository.refreshTitle(bookmarkId);
  }

  Future<Bookmark?> clearBookmarkNote(String bookmarkId) {
    return _repository.clearNote(bookmarkId);
  }

  Future<int> refreshStaleTitles({
    required int refreshDays,
    int maxConcurrent = 8,
    BookmarkProgressCallback? onProgress,
  }) {
    return _repository.refreshTitlesOlderThanWithProgress(
      Duration(days: refreshDays),
      maxConcurrent: maxConcurrent,
      onProgress: onProgress,
    );
  }

  Future<int> refreshAllTitles({
    int maxConcurrent = 10,
    BookmarkProgressCallback? onProgress,
  }) {
    return _repository.refreshAllTitlesWithProgress(
      maxConcurrent: maxConcurrent,
      onProgress: onProgress,
    );
  }

  Future<int> refreshTitlesForBookmarks(
    List<String> bookmarkIds, {
    int maxConcurrent = 10,
    BookmarkProgressCallback? onProgress,
  }) {
    return _repository.refreshTitlesByIdsWithProgress(
      bookmarkIds,
      maxConcurrent: maxConcurrent,
      onProgress: onProgress,
    );
  }

  Future<int> deleteBookmarks(List<String> bookmarkIds) {
    return _repository.softDeleteMany(bookmarkIds);
  }

  Future<int> restoreBookmarks(List<String> bookmarkIds) {
    return _repository.restoreFromTrashMany(bookmarkIds);
  }

  Future<int> permanentlyDeleteTrash(List<String> bookmarkIds) {
    return _repository.permanentlyDeleteFromTrashMany(bookmarkIds);
  }

  Future<int> emptyTrash() {
    return _repository.emptyTrash();
  }

  Future<ExportResult> exportAll({
    required ExportFormat format,
    required String targetPath,
    bool includeTrash = false,
  }) async {
    final List<Bookmark> data = includeTrash
        ? await _repository.listBookmarks(includeDeleted: true)
        : await _repository.listBookmarks();
    return _exportService.exportBookmarks(
      bookmarks: data,
      format: format,
      targetPath: targetPath,
    );
  }

  Future<ExportResult> exportSelected({
    required List<String> bookmarkIds,
    required bool fromTrash,
    required ExportFormat format,
    required String targetPath,
  }) async {
    final Set<String> idSet = bookmarkIds.map((String id) => id.trim()).toSet();
    final List<Bookmark> source = fromTrash
        ? await _repository.listTrashBookmarks()
        : await _repository.listBookmarks();
    final List<Bookmark> selected =
        source.where((Bookmark b) => idSet.contains(b.id)).toList();
    return _exportService.exportBookmarks(
      bookmarks: selected,
      format: format,
      targetPath: targetPath,
    );
  }

  String buildMarkdownContent(List<Bookmark> bookmarks) {
    return _exportService.buildMarkdownContent(bookmarks);
  }

  Future<void> clearAllData() {
    return _repository.clearAllData();
  }

  void dispose() {
    _repository.dispose();
  }
}
