import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bookmark/bookmark_title_fetcher.dart';
import '../../core/db/app_database.dart';
import '../../core/i18n/app_strings.dart';
import 'data/library_providers.dart';
import 'data/library_refresh.dart';
import 'data/library_repository.dart';
import 'library_tab_view.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage>
    with SingleTickerProviderStateMixin {
  int _segment = 0;
  int _lastRefreshTick = -1;

  final GlobalKey<LibraryTabViewState<TodoListItem>> _todoKey =
      GlobalKey<LibraryTabViewState<TodoListItem>>();
  final GlobalKey<LibraryTabViewState<NoteListItem>> _noteKey =
      GlobalKey<LibraryTabViewState<NoteListItem>>();
  final GlobalKey<LibraryTabViewState<BookmarkListItem>> _bookmarkKey =
      GlobalKey<LibraryTabViewState<BookmarkListItem>>();

  final BookmarkTitleFetcher _bookmarkFetcher = BookmarkTitleFetcher();
  final Set<String> _selectedBookmarkIds = <String>{};
  List<BookmarkListItem> _bookmarkSnapshot = const <BookmarkListItem>[];

  late final AnimationController _fadeController;

  bool _bookmarkSelectionMode = false;
  bool _bookmarkRefreshing = false;
  bool _bookmarkCancelRequested = false;
  int _bookmarkProgressDone = 0;
  int _bookmarkProgressTotal = 0;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
      value: 1,
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int refreshTick = ref.watch(libraryRefreshTickProvider);
    if (refreshTick != _lastRefreshTick) {
      _lastRefreshTick = refreshTick;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _reloadAllTabs();
        }
      });
    }

    final LibraryRepository repository = ref.watch(libraryRepositoryProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text(AppStrings.todoTab)),
                    ButtonSegment(value: 1, label: Text(AppStrings.noteTab)),
                    ButtonSegment(
                      value: 2,
                      label: Text(AppStrings.bookmarkTab),
                    ),
                  ],
                  selected: {_segment},
                  onSelectionChanged: (Set<int> values) {
                    setState(() {
                      _segment = values.first;
                      if (_segment != 2) {
                        _bookmarkSelectionMode = false;
                        _selectedBookmarkIds.clear();
                      }
                    });
                    _fadeController.forward(from: 0);
                  },
                ),
              ),
              if (kDebugMode)
                PopupMenuButton<String>(
                  tooltip: AppStrings.debugMenuTooltip,
                  onSelected: (String value) async {
                    if (value == 'seed') {
                      await _runSeed(repository);
                    }
                    if (value == 'clear') {
                      await _runClear(repository);
                    }
                  },
                  itemBuilder: (BuildContext context) => const [
                    PopupMenuItem<String>(
                      value: 'seed',
                      child: Text(AppStrings.debugSeed),
                    ),
                    PopupMenuItem<String>(
                      value: 'clear',
                      child: Text(AppStrings.debugClear),
                    ),
                  ],
                ),
            ],
          ),
          if (_segment == 2) ...[
            const SizedBox(height: 8),
            _buildBookmarkToolbar(repository),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: _fadeController,
                curve: Curves.easeOut,
              ),
              child: IndexedStack(
                index: _segment,
                children: [
                  LibraryTabView<TodoListItem>(
                    key: _todoKey,
                    pageLoader: (int page, int pageSize) =>
                        repository.listTodos(page: page, pageSize: pageSize),
                    emptyText: AppStrings.emptyTodos,
                    itemBuilder: (BuildContext context, TodoListItem item) {
                      return _TodoTile(
                        item: item,
                        onToggleDone: (bool done) async {
                          await repository.setTodoStatus(
                            todoId: item.id,
                            done: done,
                          );
                          await _todoKey.currentState?.reload();
                        },
                      );
                    },
                  ),
                  LibraryTabView<NoteListItem>(
                    key: _noteKey,
                    pageLoader: (int page, int pageSize) =>
                        repository.listNotes(page: page, pageSize: pageSize),
                    emptyText: AppStrings.emptyNotes,
                    itemBuilder: (BuildContext context, NoteListItem item) {
                      return _NoteTile(item: item);
                    },
                  ),
                  LibraryTabView<BookmarkListItem>(
                    key: _bookmarkKey,
                    pageLoader: (int page, int pageSize) => repository
                        .listBookmarks(page: page, pageSize: pageSize),
                    emptyText: AppStrings.emptyBookmarks,
                    onItemsSnapshot: (List<BookmarkListItem> items) {
                      setState(() {
                        _bookmarkSnapshot = items;
                        _selectedBookmarkIds.removeWhere(
                          (String id) =>
                              !items.any((BookmarkListItem e) => e.id == id),
                        );
                      });
                    },
                    itemBuilder: (BuildContext context, BookmarkListItem item) {
                      return _BookmarkTile(
                        item: item,
                        selectionMode: _bookmarkSelectionMode,
                        selected: _selectedBookmarkIds.contains(item.id),
                        onSelectChanged: (bool selected) {
                          setState(() {
                            if (selected) {
                              _selectedBookmarkIds.add(item.id);
                            } else {
                              _selectedBookmarkIds.remove(item.id);
                            }
                          });
                        },
                        onRefreshTitle: _bookmarkRefreshing
                            ? null
                            : () => _refreshSingleBookmark(repository, item.id),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookmarkToolbar(LibraryRepository repository) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: _bookmarkRefreshing
                  ? null
                  : () {
                      setState(() {
                        _bookmarkSelectionMode = !_bookmarkSelectionMode;
                        if (!_bookmarkSelectionMode) {
                          _selectedBookmarkIds.clear();
                        }
                      });
                    },
              child: Text(
                _bookmarkSelectionMode
                    ? AppStrings.bookmarkExitSelect
                    : AppStrings.bookmarkSelectMode,
              ),
            ),
            if (_bookmarkSelectionMode)
              OutlinedButton(
                onPressed: _bookmarkRefreshing || _bookmarkSnapshot.isEmpty
                    ? null
                    : () {
                        setState(() {
                          _selectedBookmarkIds
                            ..clear()
                            ..addAll(_bookmarkSnapshot.map((e) => e.id));
                        });
                      },
                child: const Text(AppStrings.bookmarkSelectAll),
              ),
            if (_bookmarkSelectionMode)
              FilledButton(
                onPressed: _bookmarkRefreshing || _selectedBookmarkIds.isEmpty
                    ? null
                    : () => _refreshSelectedBookmarks(repository),
                child: const Text(AppStrings.bookmarkRefreshSelected),
              ),
            if (_bookmarkRefreshing)
              TextButton(
                onPressed: () {
                  setState(() {
                    _bookmarkCancelRequested = true;
                  });
                },
                child: const Text(AppStrings.bookmarkCancelQueue),
              ),
          ],
        ),
        if (_bookmarkRefreshing) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _bookmarkProgressTotal == 0
                ? null
                : _bookmarkProgressDone / _bookmarkProgressTotal,
          ),
          const SizedBox(height: 4),
          Text('$_bookmarkProgressDone / $_bookmarkProgressTotal'),
        ],
      ],
    );
  }

  Future<void> _refreshSingleBookmark(
    LibraryRepository repository,
    String bookmarkId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await repository.refreshBookmarkTitle(
        bookmarkId: bookmarkId,
        fetcher: _bookmarkFetcher,
      );
      await _bookmarkKey.currentState?.reload();
      messenger.showSnackBar(const SnackBar(content: Text('标题刷新成功')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('标题刷新失败：$error')));
    }
  }

  Future<void> _refreshSelectedBookmarks(LibraryRepository repository) async {
    setState(() {
      _bookmarkRefreshing = true;
      _bookmarkCancelRequested = false;
      _bookmarkProgressDone = 0;
      _bookmarkProgressTotal = _selectedBookmarkIds.length;
    });

    final messenger = ScaffoldMessenger.of(context);
    final List<String> ids = _selectedBookmarkIds.toList(growable: false);

    for (final String id in ids) {
      if (_bookmarkCancelRequested) {
        break;
      }
      try {
        await repository.refreshBookmarkTitle(
          bookmarkId: id,
          fetcher: _bookmarkFetcher,
        );
      } catch (_) {
        // Continue the queue even if one item fails.
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _bookmarkProgressDone += 1;
      });
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _bookmarkRefreshing = false;
      _bookmarkSelectionMode = false;
      _selectedBookmarkIds.clear();
    });

    await _bookmarkKey.currentState?.reload();
    messenger.showSnackBar(
      SnackBar(content: Text(_bookmarkCancelRequested ? '已取消后续刷新' : '批量刷新完成')),
    );
  }

  Future<void> _runSeed(LibraryRepository repository) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text(AppStrings.seedInProgress)),
    );
    await repository.seedDebugData();
    await _reloadAllTabs();
    messenger.showSnackBar(const SnackBar(content: Text(AppStrings.seedDone)));
  }

  Future<void> _runClear(LibraryRepository repository) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text(AppStrings.clearInProgress)),
    );
    await repository.clearLibraryData();
    await _reloadAllTabs();
    messenger.showSnackBar(const SnackBar(content: Text(AppStrings.clearDone)));
  }

  Future<void> _reloadAllTabs() async {
    await Future.wait([
      _todoKey.currentState?.reload() ?? Future<void>.value(),
      _noteKey.currentState?.reload() ?? Future<void>.value(),
      _bookmarkKey.currentState?.reload() ?? Future<void>.value(),
    ]);
  }
}

class _TodoTile extends StatelessWidget {
  const _TodoTile({required this.item, required this.onToggleDone});

  final TodoListItem item;
  final ValueChanged<bool> onToggleDone;

  @override
  Widget build(BuildContext context) {
    final (String priorityText, Color priorityColor) = switch (item.priority) {
      TodoPriorityCode.high => ('高', Colors.red),
      TodoPriorityCode.medium => ('中', Colors.orange),
      _ => ('低', Colors.green),
    };

    final bool done = item.status == TodoStatusCode.done;
    final TextStyle? titleStyle = done
        ? const TextStyle(
            decoration: TextDecoration.lineThrough,
            color: Colors.black54,
          )
        : null;

    return ListTile(
      dense: true,
      leading: Checkbox(
        value: done,
        onChanged: (bool? value) => onToggleDone(value ?? false),
      ),
      title: Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: titleStyle,
      ),
      subtitle: Row(
        children: [
          Text(done ? AppStrings.statusDone : AppStrings.statusOpen),
          const SizedBox(width: 8),
          Text('标签 ${item.tagCount}'),
        ],
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: priorityColor.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(priorityText, style: TextStyle(color: priorityColor)),
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.item});

  final NoteListItem item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: const Text(AppStrings.noteOrganizedOnly),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blueGrey.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('v${item.latestVersion}'),
      ),
    );
  }
}

class _BookmarkTile extends StatelessWidget {
  const _BookmarkTile({
    required this.item,
    required this.selectionMode,
    required this.selected,
    required this.onSelectChanged,
    required this.onRefreshTitle,
  });

  final BookmarkListItem item;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool> onSelectChanged;
  final VoidCallback? onRefreshTitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: selectionMode
          ? Checkbox(
              value: selected,
              onChanged: (bool? value) => onSelectChanged(value ?? false),
            )
          : null,
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(item.url, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        icon: const Icon(Icons.refresh),
        tooltip: AppStrings.bookmarkRefreshOne,
        onPressed: onRefreshTitle,
      ),
      onTap: selectionMode ? () => onSelectChanged(!selected) : null,
    );
  }
}
