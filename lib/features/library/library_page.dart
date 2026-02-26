import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/i18n/app_strings.dart';
import 'data/library_providers.dart';
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

  final GlobalKey<LibraryTabViewState<TodoListItem>> _todoKey =
      GlobalKey<LibraryTabViewState<TodoListItem>>();
  final GlobalKey<LibraryTabViewState<NoteListItem>> _noteKey =
      GlobalKey<LibraryTabViewState<NoteListItem>>();
  final GlobalKey<LibraryTabViewState<BookmarkListItem>> _bookmarkKey =
      GlobalKey<LibraryTabViewState<BookmarkListItem>>();

  late final AnimationController _fadeController;

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
                      return _TodoTile(item: item);
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
                    itemBuilder: (BuildContext context, BookmarkListItem item) {
                      return _BookmarkTile(item: item);
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
  const _TodoTile({required this.item});

  final TodoListItem item;

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
          const Text(AppStrings.tagCountPlaceholder),
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
  const _BookmarkTile({required this.item});

  final BookmarkListItem item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(item.url, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.open_in_new_outlined, size: 18),
    );
  }
}
