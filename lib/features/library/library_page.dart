import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_provider_providers.dart';
import '../../core/ai/ai_provider_repository.dart';
import '../../core/ai/prompts.dart';
import '../../core/bookmark/bookmark_title_fetcher.dart';
import '../../core/db/app_database.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/utils/url_opener.dart';
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
                        onTap: () => _openTodoDetail(repository, item.id),
                        onToggleDone: (bool done) =>
                            _toggleTodoStatus(repository, item, done),
                      );
                    },
                  ),
                  LibraryTabView<NoteListItem>(
                    key: _noteKey,
                    pageLoader: (int page, int pageSize) =>
                        repository.listNotes(page: page, pageSize: pageSize),
                    emptyText: AppStrings.emptyNotes,
                    itemBuilder: (BuildContext context, NoteListItem item) {
                      return _NoteTile(
                        item: item,
                        onTap: () => _openNoteDetail(repository, item.id),
                      );
                    },
                  ),
                  LibraryTabView<BookmarkListItem>(
                    key: _bookmarkKey,
                    pageLoader: (int page, int pageSize) => repository
                        .listBookmarks(page: page, pageSize: pageSize),
                    emptyText: AppStrings.emptyBookmarks,
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
                        onOpenDetail: () =>
                            _openBookmarkDetail(repository, item.id),
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

  Future<void> _reloadAllTabs() async {
    await Future.wait([
      _todoKey.currentState?.reload() ?? Future<void>.value(),
      _noteKey.currentState?.reload() ?? Future<void>.value(),
      _bookmarkKey.currentState?.reload() ?? Future<void>.value(),
    ]);
  }

  Future<void> _openTodoDetail(
    LibraryRepository repository,
    String todoId,
  ) async {
    final TodoDetail? detail = await repository.getTodoDetail(todoId);
    if (!mounted) {
      return;
    }
    if (detail == null) {
      _showSnackBar(AppStrings.detailLoadFailed);
      return;
    }

    final TextEditingController titleController = TextEditingController(
      text: detail.title,
    );
    final TextEditingController tagsController = TextEditingController(
      text: detail.tags.join(', '),
    );

    int priority = detail.priority;
    bool done = detail.status == TodoStatusCode.done;
    int? remindAt = detail.remindAt;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateDialog) {
            Future<void> save() async {
              if (saving) {
                return;
              }
              setStateDialog(() {
                saving = true;
              });
              try {
                await repository.updateTodoDetail(
                  todoId: todoId,
                  title: titleController.text.trim(),
                  priority: priority,
                  status: done ? TodoStatusCode.done : TodoStatusCode.open,
                  remindAt: remindAt,
                  tags: _parseTags(tagsController.text),
                );
                await _todoKey.currentState?.reload();
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                _showSnackBar(AppStrings.saveSuccess);
              } catch (error) {
                if (dialogContext.mounted) {
                  _showSnackBar('${AppStrings.operationFailedPrefix}$error');
                }
                setStateDialog(() {
                  saving = false;
                });
              }
            }

            Future<void> pickRemindAt() async {
              final DateTime now = DateTime.now();
              final DateTime initial = remindAt == null
                  ? now
                  : DateTime.fromMillisecondsSinceEpoch(remindAt!).toLocal();
              final DateTime? date = await showDatePicker(
                context: dialogContext,
                initialDate: initial,
                firstDate: DateTime(now.year - 2),
                lastDate: DateTime(now.year + 5),
              );
              if (date == null || !dialogContext.mounted) {
                return;
              }
              final TimeOfDay? time = await showTimePicker(
                context: dialogContext,
                initialTime: TimeOfDay.fromDateTime(initial),
              );
              if (time == null) {
                return;
              }
              setStateDialog(() {
                final DateTime combined = DateTime(
                  date.year,
                  date.month,
                  date.day,
                  time.hour,
                  time.minute,
                );
                remindAt = combined.millisecondsSinceEpoch;
              });
            }

            Future<void> deleteTodo() async {
              final bool confirmed = await _confirmDelete(
                AppStrings.deleteConfirmTodo,
              );
              if (!confirmed) {
                return;
              }
              try {
                await repository.deleteTodo(todoId);
                await _todoKey.currentState?.reload();
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                _showSnackBar(AppStrings.deleteSuccess);
              } catch (error) {
                _showSnackBar('${AppStrings.operationFailedPrefix}$error');
              }
            }

            final Widget dialog = AlertDialog(
              title: const Text(AppStrings.todoDetailTitle),
              content: SizedBox(
                width: 540,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(
                          labelText: AppStrings.fieldTitle,
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => save(),
                      ),
                      const SizedBox(height: 10),
                      const Text(AppStrings.fieldPriority),
                      const SizedBox(height: 6),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(
                            value: TodoPriorityCode.high,
                            label: Text(AppStrings.priorityHigh),
                          ),
                          ButtonSegment(
                            value: TodoPriorityCode.medium,
                            label: Text(AppStrings.priorityMedium),
                          ),
                          ButtonSegment(
                            value: TodoPriorityCode.low,
                            label: Text(AppStrings.priorityLow),
                          ),
                        ],
                        selected: <int>{priority},
                        onSelectionChanged: (Set<int> values) {
                          setStateDialog(() {
                            priority = values.first;
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Text(AppStrings.fieldStatus),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text(AppStrings.statusOpen),
                            selected: !done,
                            onSelected: (bool selected) {
                              if (!selected) {
                                return;
                              }
                              setStateDialog(() {
                                done = false;
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text(AppStrings.statusDone),
                            selected: done,
                            onSelected: (bool selected) {
                              if (!selected) {
                                return;
                              }
                              setStateDialog(() {
                                done = true;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: tagsController,
                        decoration: const InputDecoration(
                          labelText: AppStrings.fieldTags,
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => save(),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${AppStrings.fieldRemindAt}: ${remindAt == null ? '未设置' : _formatTimestamp(remindAt!)}',
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: pickRemindAt,
                            child: const Text(AppStrings.setRemindAt),
                          ),
                          OutlinedButton(
                            onPressed: () {
                              setStateDialog(() {
                                remindAt = null;
                              });
                            },
                            child: const Text(AppStrings.clearRemindAt),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '${AppStrings.enterToSave} · ${AppStrings.quickSave} · ${AppStrings.escToClose}',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: titleController.text.trim()),
                    );
                    _showSnackBar(AppStrings.copied);
                  },
                  child: const Text(AppStrings.copyTitle),
                ),
                TextButton(
                  onPressed: saving ? null : deleteTodo,
                  child: const Text(AppStrings.delete),
                ),
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text(AppStrings.cancel),
                ),
                FilledButton(
                  onPressed: saving ? null : save,
                  child: Text(
                    saving
                        ? '${AppStrings.saveChanges}...'
                        : AppStrings.saveChanges,
                  ),
                ),
              ],
            );

            return _DialogKeyBindings(onSave: save, child: dialog);
          },
        );
      },
    );

    titleController.dispose();
    tagsController.dispose();
  }

  Future<void> _openBookmarkDetail(
    LibraryRepository repository,
    String bookmarkId,
  ) async {
    final BookmarkDetail? detail = await repository.getBookmarkDetail(
      bookmarkId,
    );
    if (!mounted) {
      return;
    }
    if (detail == null) {
      _showSnackBar(AppStrings.detailLoadFailed);
      return;
    }

    String title = detail.title;
    String url = detail.url;
    int? lastFetchedAt = detail.lastFetchedAt;
    final TextEditingController tagsController = TextEditingController(
      text: detail.tags.join(', '),
    );

    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateDialog) {
            Future<void> saveTags() async {
              if (saving) {
                return;
              }
              setStateDialog(() {
                saving = true;
              });
              try {
                await repository.updateBookmarkTags(
                  bookmarkId: bookmarkId,
                  tags: _parseTags(tagsController.text),
                );
                await _bookmarkKey.currentState?.reload();
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                _showSnackBar(AppStrings.saveSuccess);
              } catch (error) {
                _showSnackBar('${AppStrings.operationFailedPrefix}$error');
                setStateDialog(() {
                  saving = false;
                });
              }
            }

            Future<void> refreshTitle() async {
              setStateDialog(() {
                saving = true;
              });
              try {
                await repository.refreshBookmarkTitle(
                  bookmarkId: bookmarkId,
                  fetcher: _bookmarkFetcher,
                );
                final BookmarkDetail? updated = await repository
                    .getBookmarkDetail(bookmarkId);
                if (updated != null) {
                  setStateDialog(() {
                    title = updated.title;
                    url = updated.url;
                    lastFetchedAt = updated.lastFetchedAt;
                    saving = false;
                  });
                } else {
                  setStateDialog(() {
                    saving = false;
                  });
                }
                await _bookmarkKey.currentState?.reload();
                _showSnackBar('标题刷新成功');
              } catch (error) {
                setStateDialog(() {
                  saving = false;
                });
                _showSnackBar('标题刷新失败：$error');
              }
            }

            Future<void> deleteBookmark() async {
              final bool confirmed = await _confirmDelete(
                AppStrings.deleteConfirmBookmark,
              );
              if (!confirmed) {
                return;
              }
              try {
                await repository.deleteBookmark(bookmarkId);
                await _bookmarkKey.currentState?.reload();
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                _showSnackBar(AppStrings.deleteSuccess);
              } catch (error) {
                _showSnackBar('${AppStrings.operationFailedPrefix}$error');
              }
            }

            final Widget dialog = AlertDialog(
              title: const Text(AppStrings.bookmarkDetailTitle),
              content: SizedBox(
                width: 580,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      const Text(AppStrings.fieldUrl),
                      SelectableText(url),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () async {
                              try {
                                await UrlOpener.open(url);
                              } catch (error) {
                                _showSnackBar(
                                  '${AppStrings.operationFailedPrefix}$error',
                                );
                              }
                            },
                            child: const Text(AppStrings.bookmarkOpenUrl),
                          ),
                          OutlinedButton(
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: url));
                              _showSnackBar(AppStrings.copied);
                            },
                            child: const Text(AppStrings.bookmarkCopyUrl),
                          ),
                          OutlinedButton(
                            onPressed: saving ? null : refreshTitle,
                            child: const Text(AppStrings.bookmarkRefreshOne),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${AppStrings.bookmarkLastFetchedAt}: ${lastFetchedAt == null ? AppStrings.bookmarkNotFetched : _formatTimestamp(lastFetchedAt!)}',
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: tagsController,
                        decoration: const InputDecoration(
                          labelText: AppStrings.fieldTags,
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => saveTags(),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '${AppStrings.enterToSave} · ${AppStrings.quickSave} · ${AppStrings.escToClose}',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : deleteBookmark,
                  child: const Text(AppStrings.delete),
                ),
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text(AppStrings.cancel),
                ),
                FilledButton(
                  onPressed: saving ? null : saveTags,
                  child: Text(
                    saving
                        ? '${AppStrings.saveChanges}...'
                        : AppStrings.saveChanges,
                  ),
                ),
              ],
            );

            return _DialogKeyBindings(onSave: saveTags, child: dialog);
          },
        );
      },
    );

    tagsController.dispose();
  }

  Future<void> _openNoteDetail(
    LibraryRepository repository,
    String noteId,
  ) async {
    final NoteDetail? detail = await repository.getNoteDetail(noteId);
    if (!mounted || detail == null) {
      return;
    }

    bool showRaw = false;
    String organized = detail.organizedMd;
    int version = detail.latestVersion;
    bool regenerating = false;

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateDialog) {
            return AlertDialog(
              title: Text('${AppStrings.noteDetailTitle} v$version'),
              content: SizedBox(
                width: 640,
                child: SingleChildScrollView(
                  child: Text(showRaw ? detail.rawText : organized),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setStateDialog(() {
                      showRaw = !showRaw;
                    });
                  },
                  child: const Text(AppStrings.noteViewRaw),
                ),
                TextButton(
                  onPressed: regenerating
                      ? null
                      : () async {
                          setStateDialog(() {
                            regenerating = true;
                          });
                          try {
                            final AiProviderRepository providerRepo = ref.read(
                              aiProviderRepositoryProvider,
                            );
                            final cfg = await providerRepo.load();
                            if (!cfg.isReady ||
                                cfg.selectedModel.trim().isEmpty) {
                              throw Exception(AppStrings.inboxNeedModel);
                            }
                            final client = ref.read(aiProviderClientProvider);
                            final String newMd = await client.generateText(
                              config: cfg,
                              model: cfg.selectedModel,
                              systemPrompt:
                                  '${AiPrompts.routerSystemPrompt}\n'
                                  '你现在只做笔记整理，请输出 Markdown 正文，不要输出代码围栏。',
                              userPrompt: detail.rawText,
                              maxTokens: 1200,
                            );
                            await repository.appendNoteVersion(
                              noteId: noteId,
                              organizedMd: newMd,
                            );
                            final updated = await repository.getNoteDetail(
                              noteId,
                            );
                            if (updated != null) {
                              setStateDialog(() {
                                organized = updated.organizedMd;
                                version = updated.latestVersion;
                                showRaw = false;
                              });
                            }
                            await _noteKey.currentState?.reload();
                          } catch (error) {
                            if (context.mounted) {
                              _showSnackBar('重新整理失败：$error');
                            }
                          } finally {
                            setStateDialog(() {
                              regenerating = false;
                            });
                          }
                        },
                  child: Text(
                    regenerating
                        ? '${AppStrings.noteReorganize}...'
                        : AppStrings.noteReorganize,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _confirmDelete(String message) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(AppStrings.deleteConfirmTitle),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(AppStrings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(AppStrings.confirm),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  List<String> _parseTags(String input) {
    return input
        .split(',')
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  String _formatTimestamp(int value) {
    final DateTime dt = DateTime.fromMillisecondsSinceEpoch(value).toLocal();
    final String month = dt.month.toString().padLeft(2, '0');
    final String day = dt.day.toString().padLeft(2, '0');
    final String hour = dt.hour.toString().padLeft(2, '0');
    final String minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$month-$day $hour:$minute';
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

class _SaveIntent extends Intent {
  const _SaveIntent();
}

class _DialogKeyBindings extends StatelessWidget {
  const _DialogKeyBindings({required this.onSave, required this.child});

  final Future<void> Function() onSave;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter, control: true): _SaveIntent(),
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _SaveIntent: CallbackAction<_SaveIntent>(
            onInvoke: (_SaveIntent intent) {
              onSave();
              return null;
            },
          ),
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (DismissIntent intent) {
              Navigator.of(context).maybePop();
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}
