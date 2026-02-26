import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/i18n/app_strings.dart';
import '../library/data/library_providers.dart';
import '../library/data/library_repository.dart';

class TodoDetailPage extends ConsumerStatefulWidget {
  const TodoDetailPage({super.key, required this.todoId});

  final String todoId;

  @override
  ConsumerState<TodoDetailPage> createState() => _TodoDetailPageState();
}

class _TodoDetailPageState extends ConsumerState<TodoDetailPage> {
  TodoDetail? _detail;
  bool _loading = true;
  bool _saving = false;
  bool _editing = false;
  bool _dirty = false;

  late final TextEditingController _titleController;
  late final TextEditingController _tagsController;

  int _priority = TodoPriorityCode.medium;
  bool _done = false;
  int? _remindAt;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _tagsController = TextEditingController();
    _loadDetail();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _loadDetail() async {
    final LibraryRepository repository = ref.read(libraryRepositoryProvider);
    final TodoDetail? detail = await repository.getTodoDetail(widget.todoId);
    if (!mounted) {
      return;
    }
    setState(() {
      _detail = detail;
      _loading = false;
    });
    if (detail != null) {
      _resetEditDraft(detail);
    }
  }

  void _resetEditDraft(TodoDetail detail) {
    _titleController.text = detail.title;
    _tagsController.text = detail.tags.join(', ');
    _priority = detail.priority;
    _done = detail.status == TodoStatusCode.done;
    _remindAt = detail.remindAt;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, bool? result) {
        if (didPop) {
          return;
        }
        Navigator.of(context).pop(_dirty);
      },
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter, control: true):
              _TodoSaveIntent(),
          SingleActivator(LogicalKeyboardKey.escape): _TodoCancelIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _TodoSaveIntent: CallbackAction<_TodoSaveIntent>(
              onInvoke: (_TodoSaveIntent intent) {
                if (_editing) {
                  _saveChanges();
                }
                return null;
              },
            ),
            _TodoCancelIntent: CallbackAction<_TodoCancelIntent>(
              onInvoke: (_TodoCancelIntent intent) {
                if (_editing) {
                  _cancelEdit();
                  return null;
                }
                Navigator.of(context).pop(_dirty);
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              appBar: AppBar(
                title: const Text(AppStrings.todoDetailTitle),
                actions: _buildActions(context),
              ),
              body: _buildBody(context),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    if (_detail == null) {
      return const <Widget>[];
    }
    if (_editing) {
      return <Widget>[
        TextButton(
          onPressed: _saving ? null : _cancelEdit,
          child: const Text(AppStrings.cancel),
        ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: FilledButton(
            onPressed: _saving ? null : _saveChanges,
            child: Text(_saving ? '${AppStrings.save}...' : AppStrings.save),
          ),
        ),
      ];
    }

    return <Widget>[
      IconButton(
        tooltip: _done ? AppStrings.statusOpen : AppStrings.statusDone,
        onPressed: _saving ? null : _toggleDoneQuick,
        icon: Icon(_done ? Icons.check_circle : Icons.radio_button_unchecked),
      ),
      IconButton(
        tooltip: AppStrings.copyTitle,
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: _detail!.title));
          if (!context.mounted) {
            return;
          }
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text(AppStrings.copied)));
        },
        icon: const Icon(Icons.copy_outlined),
      ),
      IconButton(
        tooltip: AppStrings.saveChanges,
        onPressed: _saving
            ? null
            : () {
                setState(() {
                  _editing = true;
                });
              },
        icon: const Icon(Icons.edit_outlined),
      ),
      IconButton(
        tooltip: AppStrings.delete,
        onPressed: _saving ? null : _deleteTodo,
        icon: const Icon(Icons.delete_outline),
      ),
      const SizedBox(width: 4),
    ];
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final TodoDetail? detail = _detail;
    if (detail == null) {
      return const Center(child: Text(AppStrings.detailLoadFailed));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 140),
        child: _editing ? _buildEditForm(context) : _buildReadonly(detail),
      ),
    );
  }

  Widget _buildReadonly(TodoDetail detail) {
    final String remindAtText =
        detail.remindAt == null ? '-' : _formatTimestamp(detail.remindAt!);
    return Column(
      key: const ValueKey<String>('todo_readonly'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(detail.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        _kvLine(AppStrings.fieldPriority, _priorityLabel(detail.priority)),
        _kvLine(
          AppStrings.fieldStatus,
          detail.status == TodoStatusCode.done
              ? AppStrings.statusDone
              : AppStrings.statusOpen,
        ),
        _kvLine(AppStrings.fieldRemindAt, remindAtText),
        _kvLine(AppStrings.fieldTags, detail.tags.join(', ')),
      ],
    );
  }

  Widget _buildEditForm(BuildContext context) {
    return Column(
      key: const ValueKey<String>('todo_edit'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(labelText: AppStrings.fieldTitle),
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 10),
        const Text(AppStrings.fieldPriority),
        const SizedBox(height: 6),
        SegmentedButton<int>(
          segments: const <ButtonSegment<int>>[
            ButtonSegment<int>(
              value: TodoPriorityCode.high,
              label: Text(AppStrings.priorityHigh),
            ),
            ButtonSegment<int>(
              value: TodoPriorityCode.medium,
              label: Text(AppStrings.priorityMedium),
            ),
            ButtonSegment<int>(
              value: TodoPriorityCode.low,
              label: Text(AppStrings.priorityLow),
            ),
          ],
          selected: <int>{_priority},
          onSelectionChanged: (Set<int> values) {
            setState(() {
              _priority = values.first;
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
              selected: !_done,
              onSelected: (bool selected) {
                if (!selected) {
                  return;
                }
                setState(() {
                  _done = false;
                });
              },
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text(AppStrings.statusDone),
              selected: _done,
              onSelected: (bool selected) {
                if (!selected) {
                  return;
                }
                setState(() {
                  _done = true;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _tagsController,
          decoration: const InputDecoration(labelText: AppStrings.fieldTags),
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 10),
        Text(
          '${AppStrings.fieldRemindAt}: ${_remindAt == null ? '-' : _formatTimestamp(_remindAt!)}',
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: _pickRemindAt,
              child: const Text(AppStrings.setRemindAt),
            ),
            OutlinedButton(
              onPressed: () {
                setState(() {
                  _remindAt = null;
                });
              },
              child: const Text(AppStrings.clearRemindAt),
            ),
          ],
        ),
      ],
    );
  }

  Widget _kvLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text('$label:')),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Future<void> _pickRemindAt() async {
    final DateTime now = DateTime.now();
    final DateTime initial = _remindAt == null
        ? now
        : DateTime.fromMillisecondsSinceEpoch(_remindAt!).toLocal();
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) {
      return;
    }
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) {
      return;
    }
    setState(() {
      _remindAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ).millisecondsSinceEpoch;
    });
  }

  Future<void> _toggleDoneQuick() async {
    final TodoDetail? detail = _detail;
    if (detail == null || _saving) {
      return;
    }
    final bool nextDone = !_done;
    setState(() {
      _saving = true;
      _done = nextDone;
      _detail = TodoDetail(
        id: detail.id,
        title: detail.title,
        priority: detail.priority,
        status: nextDone ? TodoStatusCode.done : TodoStatusCode.open,
        remindAt: detail.remindAt,
        tags: detail.tags,
      );
    });

    try {
      await ref
          .read(libraryRepositoryProvider)
          .setTodoStatus(todoId: widget.todoId, done: nextDone);
      _dirty = true;
    } catch (error) {
      setState(() {
        _done = !nextDone;
        _detail = TodoDetail(
          id: detail.id,
          title: detail.title,
          priority: detail.priority,
          status: detail.status,
          remindAt: detail.remindAt,
          tags: detail.tags,
        );
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.operationFailedPrefix}$error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _saveChanges() async {
    final TodoDetail? detail = _detail;
    if (detail == null || _saving) {
      return;
    }

    final String title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AppStrings.inboxNeedInput)));
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await ref
          .read(libraryRepositoryProvider)
          .updateTodoDetail(
            todoId: detail.id,
            title: title,
            priority: _priority,
            status: _done ? TodoStatusCode.done : TodoStatusCode.open,
            remindAt: _remindAt,
            tags: _parseTags(_tagsController.text),
          );
      _dirty = true;
      await _loadDetail();
      if (!mounted) {
        return;
      }
      setState(() {
        _editing = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AppStrings.saveSuccess)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppStrings.operationFailedPrefix}$error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _cancelEdit() {
    final TodoDetail? detail = _detail;
    if (detail != null) {
      _resetEditDraft(detail);
    }
    setState(() {
      _editing = false;
    });
  }

  Future<void> _deleteTodo() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(AppStrings.deleteConfirmTitle),
          content: const Text(AppStrings.deleteConfirmTodo),
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
    if (confirmed != true) {
      return;
    }

    try {
      await ref.read(libraryRepositoryProvider).deleteTodo(widget.todoId);
      if (!mounted) {
        return;
      }
      _dirty = true;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppStrings.operationFailedPrefix}$error')),
      );
    }
  }

  List<String> _parseTags(String input) {
    return input
        .split(',')
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  String _priorityLabel(int value) {
    switch (value) {
      case TodoPriorityCode.high:
        return AppStrings.priorityHigh;
      case TodoPriorityCode.medium:
        return AppStrings.priorityMedium;
      default:
        return AppStrings.priorityLow;
    }
  }

  String _formatTimestamp(int value) {
    final DateTime dt = DateTime.fromMillisecondsSinceEpoch(value).toLocal();
    final String month = dt.month.toString().padLeft(2, '0');
    final String day = dt.day.toString().padLeft(2, '0');
    final String hour = dt.hour.toString().padLeft(2, '0');
    final String minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$month-$day $hour:$minute';
  }
}

class _TodoSaveIntent extends Intent {
  const _TodoSaveIntent();
}

class _TodoCancelIntent extends Intent {
  const _TodoCancelIntent();
}
