import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../entity_detail/entity_detail_routes.dart';
import '../../core/db/app_database.dart';
import '../../core/i18n/app_strings.dart';
import '../library/data/library_providers.dart';
import '../library/data/library_repository.dart';
import '../library/library_tab_view.dart';

enum _TagTodoFilterAction {
  toggleIncludeDone,
  remindAll,
  remindWith,
  remindWithout,
}

class TagResultPage extends ConsumerStatefulWidget {
  const TagResultPage({super.key, required this.tagId, required this.tagName});

  final String tagId;
  final String tagName;

  @override
  ConsumerState<TagResultPage> createState() => _TagResultPageState();
}

class _TagResultPageState extends ConsumerState<TagResultPage>
    with SingleTickerProviderStateMixin {
  int _segment = 0;
  bool _todoIncludeDone = false;
  TodoRemindFilter _todoRemindFilter = TodoRemindFilter.all;

  final GlobalKey<LibraryTabViewState<TodoListItem>> _todoKey =
      GlobalKey<LibraryTabViewState<TodoListItem>>();
  final GlobalKey<LibraryTabViewState<NoteListItem>> _noteKey =
      GlobalKey<LibraryTabViewState<NoteListItem>>();
  final GlobalKey<LibraryTabViewState<BookmarkListItem>> _bookmarkKey =
      GlobalKey<LibraryTabViewState<BookmarkListItem>>();

  late final AnimationController _fadeController;

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
    final LibraryRepository repository = ref.watch(libraryRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('${AppStrings.tagResultTitlePrefix}${widget.tagName}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<int>(
                    segments: const <ButtonSegment<int>>[
                      ButtonSegment<int>(
                        value: 0,
                        label: Text(AppStrings.todoTab),
                      ),
                      ButtonSegment<int>(
                        value: 1,
                        label: Text(AppStrings.noteTab),
                      ),
                      ButtonSegment<int>(
                        value: 2,
                        label: Text(AppStrings.bookmarkTab),
                      ),
                    ],
                    selected: <int>{_segment},
                    onSelectionChanged: (Set<int> values) {
                      setState(() {
                        _segment = values.first;
                      });
                      _fadeController.forward(from: 0);
                    },
                  ),
                ),
                if (_segment == 0) ...[
                  const SizedBox(width: 8),
                  _buildTodoFilterButton(),
                ],
              ],
            ),
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
                          repository.listTodosByTag(
                            tagId: widget.tagId,
                            page: page,
                            pageSize: pageSize,
                            includeDone: _todoIncludeDone,
                            remindFilter: _todoRemindFilter,
                          ),
                      emptyText: AppStrings.emptyTodos,
                      itemBuilder: (BuildContext context, TodoListItem item) {
                        return _TagTodoTile(
                          item: item,
                          onTap: () => _openTodoDetail(item.id),
                          onToggleDone: (bool done) =>
                              _toggleTodoStatus(repository, item, done),
                        );
                      },
                    ),
                    LibraryTabView<NoteListItem>(
                      key: _noteKey,
                      pageLoader: (int page, int pageSize) =>
                          repository.listNotesByTag(
                            tagId: widget.tagId,
                            page: page,
                            pageSize: pageSize,
                          ),
                      emptyText: AppStrings.emptyNotes,
                      itemBuilder: (BuildContext context, NoteListItem item) {
                        return _TagNoteTile(
                          item: item,
                          onTap: () => _openNoteDetail(item.id),
                        );
                      },
                    ),
                    LibraryTabView<BookmarkListItem>(
                      key: _bookmarkKey,
                      pageLoader: (int page, int pageSize) =>
                          repository.listBookmarksByTag(
                            tagId: widget.tagId,
                            page: page,
                            pageSize: pageSize,
                          ),
                      emptyText: AppStrings.emptyBookmarks,
                      itemBuilder:
                          (BuildContext context, BookmarkListItem item) {
                            return _TagBookmarkTile(
                              item: item,
                              onTap: () => _openBookmarkDetail(item.id),
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
    );
  }

  Widget _buildTodoFilterButton() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<_TagTodoFilterAction>(
          tooltip: AppStrings.todoFilterButton,
          onSelected: _applyTodoFilterAction,
          itemBuilder: (BuildContext context) =>
              <PopupMenuEntry<_TagTodoFilterAction>>[
                CheckedPopupMenuItem<_TagTodoFilterAction>(
                  value: _TagTodoFilterAction.toggleIncludeDone,
                  checked: _todoIncludeDone,
                  child: const Text(AppStrings.todoFilterShowDone),
                ),
                const PopupMenuDivider(),
                CheckedPopupMenuItem<_TagTodoFilterAction>(
                  value: _TagTodoFilterAction.remindAll,
                  checked: _todoRemindFilter == TodoRemindFilter.all,
                  child: const Text(AppStrings.todoFilterRemindAll),
                ),
                CheckedPopupMenuItem<_TagTodoFilterAction>(
                  value: _TagTodoFilterAction.remindWith,
                  checked: _todoRemindFilter == TodoRemindFilter.withRemind,
                  child: const Text(AppStrings.todoFilterRemindWith),
                ),
                CheckedPopupMenuItem<_TagTodoFilterAction>(
                  value: _TagTodoFilterAction.remindWithout,
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

  Future<void> _applyTodoFilterAction(_TagTodoFilterAction action) async {
    bool nextIncludeDone = _todoIncludeDone;
    TodoRemindFilter nextRemindFilter = _todoRemindFilter;

    switch (action) {
      case _TagTodoFilterAction.toggleIncludeDone:
        nextIncludeDone = !nextIncludeDone;
        break;
      case _TagTodoFilterAction.remindAll:
        nextRemindFilter = TodoRemindFilter.all;
        break;
      case _TagTodoFilterAction.remindWith:
        nextRemindFilter = TodoRemindFilter.withRemind;
        break;
      case _TagTodoFilterAction.remindWithout:
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
    } catch (_) {
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
}

class _TagTodoTile extends StatelessWidget {
  const _TagTodoTile({
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

class _TagNoteTile extends StatelessWidget {
  const _TagNoteTile({required this.item, required this.onTap});

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

class _TagBookmarkTile extends StatelessWidget {
  const _TagBookmarkTile({required this.item, required this.onTap});

  final BookmarkListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(item.url, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}
