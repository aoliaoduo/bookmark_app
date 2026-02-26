import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../entity_detail/entity_detail_routes.dart';
import '../../core/bookmark/bookmark_title_fetcher.dart';
import '../../core/db/app_database.dart';
import '../../core/i18n/app_strings.dart';
import 'data/library_providers.dart';
import 'data/library_refresh.dart';
import 'data/library_repository.dart';
import 'library_tab_view.dart';

enum _TodoFilterAction {
  toggleIncludeDone,
  remindAll,
  remindWith,
  remindWithout,
}

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

  late final AnimationController _fadeController;

  bool _bookmarkSelectionMode = false;
  bool _bookmarkRefreshing = false;
  bool _bookmarkCancelRequested = false;
  int _bookmarkProgressDone = 0;
  int _bookmarkProgressTotal = 0;
  bool _todoIncludeDone = false;
  TodoRemindFilter _todoRemindFilter = TodoRemindFilter.all;

  int get _todoFilterActiveCount {
    int count = 0;
    if (_todoIncludeDone) {
      count += 1;
    }
    if (_todoRemindFilter != TodoRemindFilter.all) {
      count += 1;
    }
    return count;
  }

  bool get _todoFilterActive => _todoFilterActiveCount > 0;

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

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): _ExitBookmarkSelectIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _ExitBookmarkSelectIntent: CallbackAction<_ExitBookmarkSelectIntent>(
            onInvoke: (_ExitBookmarkSelectIntent intent) {
              if (_bookmarkSelectionMode) {
                setState(() {
                  _bookmarkSelectionMode = false;
                  _selectedBookmarkIds.clear();
                });
                return null;
              }
              Navigator.of(context).maybePop();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(
                            value: 0,
                            label: Text(AppStrings.todoTab),
                          ),
                          ButtonSegment(
                            value: 1,
                            label: Text(AppStrings.noteTab),
                          ),
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
                    if (_segment == 0) ...[
                      const SizedBox(width: 8),
                      _buildTodoFilterButton(),
                    ],
                    if (kDebugMode) ...[
                      const SizedBox(width: 8),
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
                              repository.listTodos(
                                page: page,
                                pageSize: pageSize,
                                includeDone: _todoIncludeDone,
                                remindFilter: _todoRemindFilter,
                              ),
                          emptyText: AppStrings.emptyTodos,
                          itemBuilder:
                              (BuildContext context, TodoListItem item) {
                                return _TodoTile(
                                  item: item,
                                  onTap: () => _openTodoDetail(item.id),
                                  onToggleDone: (bool done) =>
                                      _toggleTodoStatus(repository, item, done),
                                );
                              },
                        ),
                        LibraryTabView<NoteListItem>(
                          key: _noteKey,
                          pageLoader: (int page, int pageSize) => repository
                              .listNotes(page: page, pageSize: pageSize),
                          emptyText: AppStrings.emptyNotes,
                          itemBuilder:
                              (BuildContext context, NoteListItem item) {
                                return _NoteTile(
                                  item: item,
                                  onTap: () => _openNoteDetail(item.id),
                                );
                              },
                        ),
                        LibraryTabView<BookmarkListItem>(
                          key: _bookmarkKey,
                          pageLoader: (int page, int pageSize) => repository
                              .listBookmarks(page: page, pageSize: pageSize),
                          emptyText: AppStrings.emptyBookmarks,
                          itemBuilder:
                              (BuildContext context, BookmarkListItem item) {
                                return _BookmarkTile(
                                  item: item,
                                  selectionMode: _bookmarkSelectionMode,
                                  selected: _selectedBookmarkIds.contains(
                                    item.id,
                                  ),
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
                                      : () => _refreshSingleBookmark(
                                          repository,
                                          item.id,
                                        ),
                                  onOpenDetail: () =>
                                      _openBookmarkDetail(item.id),
                                );
                              },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTodoFilterButton() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<_TodoFilterAction>(
          tooltip: AppStrings.todoFilterButton,
          onSelected: _applyTodoFilterAction,
          itemBuilder: (BuildContext context) =>
              <PopupMenuEntry<_TodoFilterAction>>[
                CheckedPopupMenuItem<_TodoFilterAction>(
                  value: _TodoFilterAction.toggleIncludeDone,
                  checked: _todoIncludeDone,
                  child: const Text(AppStrings.todoFilterShowDone),
                ),
                const PopupMenuDivider(),
                CheckedPopupMenuItem<_TodoFilterAction>(
                  value: _TodoFilterAction.remindAll,
                  checked: _todoRemindFilter == TodoRemindFilter.all,
                  child: const Text(AppStrings.todoFilterRemindAll),
                ),
                CheckedPopupMenuItem<_TodoFilterAction>(
                  value: _TodoFilterAction.remindWith,
                  checked: _todoRemindFilter == TodoRemindFilter.withRemind,
                  child: const Text(AppStrings.todoFilterRemindWith),
                ),
                CheckedPopupMenuItem<_TodoFilterAction>(
                  value: _TodoFilterAction.remindWithout,
                  checked: _todoRemindFilter == TodoRemindFilter.withoutRemind,
                  child: const Text(AppStrings.todoFilterRemindWithout),
                ),
              ],
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black26),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.filter_alt_outlined, size: 18),
                    SizedBox(width: 4),
                    Text(AppStrings.todoFilterButton),
                  ],
                ),
              ),
              if (_todoFilterActive)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$_todoFilterActiveCount',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_todoFilterActive) ...[
          const SizedBox(width: 6),
          TextButton(
            onPressed: _clearTodoFilters,
            child: const Text(AppStrings.todoFilterClear),
          ),
        ],
      ],
    );
  }

  Future<void> _applyTodoFilterAction(_TodoFilterAction action) async {
    bool nextIncludeDone = _todoIncludeDone;
    TodoRemindFilter nextRemindFilter = _todoRemindFilter;

    switch (action) {
      case _TodoFilterAction.toggleIncludeDone:
        nextIncludeDone = !nextIncludeDone;
        break;
      case _TodoFilterAction.remindAll:
        nextRemindFilter = TodoRemindFilter.all;
        break;
      case _TodoFilterAction.remindWith:
        nextRemindFilter = TodoRemindFilter.withRemind;
        break;
      case _TodoFilterAction.remindWithout:
        nextRemindFilter = TodoRemindFilter.withoutRemind;
        break;
    }

    if (nextIncludeDone == _todoIncludeDone &&
        nextRemindFilter == _todoRemindFilter) {
      return;
    }

    setState(() {
      _todoIncludeDone = nextIncludeDone;
      _todoRemindFilter = nextRemindFilter;
    });
    await _todoKey.currentState?.reload();
  }

  void _clearTodoFilters() {
    if (!_todoFilterActive) {
      return;
    }
    setState(() {
      _todoIncludeDone = false;
      _todoRemindFilter = TodoRemindFilter.all;
    });
    _todoKey.currentState?.reload();
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
                onPressed: _bookmarkRefreshing
                    ? null
                    : () => _selectAllBookmarks(repository),
                child: const Text('${AppStrings.bookmarkSelectAll}（全部）'),
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
        if (_bookmarkSelectionMode)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('已选择 ${_selectedBookmarkIds.length} 项'),
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
    try {
      await repository.refreshBookmarkTitle(
        bookmarkId: bookmarkId,
        fetcher: _bookmarkFetcher,
      );
      await _bookmarkKey.currentState?.reload();
      _showSnackBar('标题刷新成功');
    } catch (error) {
      _showSnackBar('标题刷新失败：$error');
    }
  }

  Future<void> _selectAllBookmarks(LibraryRepository repository) async {
    try {
      final List<String> ids = await repository.listAllBookmarkIds();
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedBookmarkIds
          ..clear()
          ..addAll(ids);
      });
    } catch (error) {
      _showSnackBar('全选失败：$error');
    }
  }

  Future<void> _refreshSelectedBookmarks(LibraryRepository repository) async {
    setState(() {
      _bookmarkRefreshing = true;
      _bookmarkCancelRequested = false;
      _bookmarkProgressDone = 0;
      _bookmarkProgressTotal = _selectedBookmarkIds.length;
    });

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
        // Keep processing queue.
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
    _showSnackBar(_bookmarkCancelRequested ? '已取消后续刷新' : '批量刷新完成');
  }

  Future<void> _runSeed(LibraryRepository repository) async {
    _showSnackBar(AppStrings.seedInProgress);
    await repository.seedDebugData();
    await _reloadAllTabs();
    _showSnackBar(AppStrings.seedDone);
  }

  Future<void> _runClear(LibraryRepository repository) async {
    _showSnackBar(AppStrings.clearInProgress);
    await repository.clearLibraryData();
    await _reloadAllTabs();
    _showSnackBar(AppStrings.clearDone);
  }

  Future<void> _toggleTodoStatus(
    LibraryRepository repository,
    TodoListItem item,
    bool done,
  ) async {
    final int prevStatus = item.status;
    final int nextStatus = done ? TodoStatusCode.done : TodoStatusCode.open;

    _todoKey.currentState?.patchItem(
      match: (TodoListItem current) => current.id == item.id,
      update: (TodoListItem current) => TodoListItem(
        id: current.id,
        title: current.title,
        priority: current.priority,
        status: nextStatus,
        tagCount: current.tagCount,
      ),
    );

    try {
      await repository.setTodoStatus(todoId: item.id, done: done);
      if (done && !_todoIncludeDone) {
        _todoKey.currentState?.removeWhere(
          (TodoListItem current) => current.id == item.id,
        );
      }
    } catch (error) {
      _todoKey.currentState?.patchItem(
        match: (TodoListItem current) => current.id == item.id,
        update: (TodoListItem current) => TodoListItem(
          id: current.id,
          title: current.title,
          priority: current.priority,
          status: prevStatus,
          tagCount: current.tagCount,
        ),
      );
      _showSnackBar('更新待办状态失败：$error');
    }
  }

  Future<void> _openTodoDetail(String todoId) async {
    final bool changed =
        (await EntityDetailRoutes.openTodo(context, todoId)) ?? false;
    if (changed) {
      await _todoKey.currentState?.reload();
    }
  }

  Future<void> _openNoteDetail(String noteId) async {
    final bool changed =
        (await EntityDetailRoutes.openNote(context, noteId)) ?? false;
    if (changed) {
      await _noteKey.currentState?.reload();
    }
  }

  Future<void> _openBookmarkDetail(String bookmarkId) async {
    final bool changed =
        (await EntityDetailRoutes.openLink(context, bookmarkId)) ?? false;
    if (changed) {
      await _bookmarkKey.currentState?.reload();
    }
  }

  Future<void> _reloadAllTabs() async {
    await Future.wait([
      _todoKey.currentState?.reload() ?? Future<void>.value(),
      _noteKey.currentState?.reload() ?? Future<void>.value(),
      _bookmarkKey.currentState?.reload() ?? Future<void>.value(),
    ]);
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _TodoTile extends StatelessWidget {
  const _TodoTile({
    required this.item,
    required this.onToggleDone,
    required this.onTap,
  });

  final TodoListItem item;
  final ValueChanged<bool> onToggleDone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (String priorityText, Color priorityColor) = switch (item.priority) {
      TodoPriorityCode.high => (AppStrings.priorityHigh, Colors.red),
      TodoPriorityCode.medium => (AppStrings.priorityMedium, Colors.orange),
      _ => (AppStrings.priorityLow, Colors.green),
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
      onTap: onTap,
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.item, required this.onTap});

  final NoteListItem item;
  final VoidCallback onTap;

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
      onTap: onTap,
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
    required this.onOpenDetail,
  });

  final BookmarkListItem item;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool> onSelectChanged;
  final VoidCallback? onRefreshTitle;
  final VoidCallback onOpenDetail;

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
      onTap: selectionMode ? () => onSelectChanged(!selected) : onOpenDetail,
    );
  }
}

class _ExitBookmarkSelectIntent extends Intent {
  const _ExitBookmarkSelectIntent();
}
