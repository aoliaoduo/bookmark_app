import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bookmark/bookmark_title_fetcher.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/utils/url_opener.dart';
import '../library/data/library_providers.dart';
import '../library/data/library_repository.dart';

class BookmarkDetailPage extends ConsumerStatefulWidget {
  const BookmarkDetailPage({super.key, required this.bookmarkId});

  final String bookmarkId;

  @override
  ConsumerState<BookmarkDetailPage> createState() => _BookmarkDetailPageState();
}

class _BookmarkDetailPageState extends ConsumerState<BookmarkDetailPage> {
  final BookmarkTitleFetcher _fetcher = BookmarkTitleFetcher();

  BookmarkDetail? _detail;
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;
  bool _dirty = false;

  late final TextEditingController _titleController;
  late final TextEditingController _urlController;
  late final TextEditingController _tagsController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _urlController = TextEditingController();
    _tagsController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final BookmarkDetail? detail = await ref
        .read(libraryRepositoryProvider)
        .getBookmarkDetail(widget.bookmarkId);
    if (!mounted) {
      return;
    }
    setState(() {
      _detail = detail;
      _loading = false;
      if (detail != null) {
        _titleController.text = detail.title;
        _urlController.text = detail.url;
        _tagsController.text = detail.tags.join(', ');
      }
    });
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
              _BookmarkSaveIntent(),
          SingleActivator(LogicalKeyboardKey.escape): _BookmarkCancelIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _BookmarkSaveIntent: CallbackAction<_BookmarkSaveIntent>(
              onInvoke: (_BookmarkSaveIntent intent) {
                if (_editing) {
                  _saveChanges();
                }
                return null;
              },
            ),
            _BookmarkCancelIntent: CallbackAction<_BookmarkCancelIntent>(
              onInvoke: (_BookmarkCancelIntent intent) {
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
                title: const Text(AppStrings.bookmarkDetailTitle),
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
    final BookmarkDetail? detail = _detail;
    if (detail == null) {
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
        tooltip: AppStrings.bookmarkRefreshOne,
        onPressed: _saving ? null : _refreshTitle,
        icon: const Icon(Icons.refresh),
      ),
      IconButton(
        tooltip: AppStrings.bookmarkCopyUrl,
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: detail.url));
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
        onPressed: () {
          setState(() {
            _editing = true;
          });
        },
        icon: const Icon(Icons.edit_outlined),
      ),
      IconButton(
        tooltip: AppStrings.delete,
        onPressed: _saving ? null : _deleteBookmark,
        icon: const Icon(Icons.delete_outline),
      ),
      const SizedBox(width: 4),
    ];
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final BookmarkDetail? detail = _detail;
    if (detail == null) {
      return const Center(child: Text(AppStrings.detailLoadFailed));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 140),
        child: _editing ? _buildEditForm() : _buildReadonly(detail),
      ),
    );
  }

  Widget _buildReadonly(BookmarkDetail detail) {
    return Column(
      key: const ValueKey<String>('bookmark_readonly'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(detail.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        const Text(AppStrings.fieldUrl),
        SelectableText(detail.url),
        const SizedBox(height: 8),
        Text(
          '${AppStrings.bookmarkLastFetchedAt}: ${detail.lastFetchedAt == null ? AppStrings.bookmarkNotFetched : _formatTimestamp(detail.lastFetchedAt!)}',
        ),
        const SizedBox(height: 8),
        Text('${AppStrings.fieldTags}: ${detail.tags.join(', ')}'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: () async {
                final ScaffoldMessengerState messenger = ScaffoldMessenger.of(
                  context,
                );
                try {
                  await UrlOpener.open(detail.url);
                } catch (error) {
                  if (!mounted) {
                    return;
                  }
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        '${AppStrings.operationFailedPrefix}$error',
                      ),
                    ),
                  );
                }
              },
              child: const Text(AppStrings.bookmarkOpenUrl),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEditForm() {
    return Column(
      key: const ValueKey<String>('bookmark_edit'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(labelText: AppStrings.fieldTitle),
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _urlController,
          decoration: const InputDecoration(labelText: AppStrings.fieldUrl),
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _tagsController,
          decoration: const InputDecoration(labelText: AppStrings.fieldTags),
          textInputAction: TextInputAction.done,
        ),
      ],
    );
  }

  Future<void> _refreshTitle() async {
    if (_saving) {
      return;
    }
    setState(() {
      _saving = true;
    });
    try {
      await ref
          .read(libraryRepositoryProvider)
          .refreshBookmarkTitle(
            bookmarkId: widget.bookmarkId,
            fetcher: _fetcher,
          );
      _dirty = true;
      await _load();
      if (!mounted) {
        return;
      }
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

  Future<void> _saveChanges() async {
    final String title = _titleController.text.trim();
    final String url = _urlController.text.trim();
    if (title.isEmpty || url.isEmpty) {
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
          .updateBookmarkDetail(
            bookmarkId: widget.bookmarkId,
            title: title,
            url: url,
            tags: _parseTags(_tagsController.text),
          );
      _dirty = true;
      await _load();
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
    final BookmarkDetail? detail = _detail;
    if (detail != null) {
      _titleController.text = detail.title;
      _urlController.text = detail.url;
      _tagsController.text = detail.tags.join(', ');
    }
    setState(() {
      _editing = false;
    });
  }

  Future<void> _deleteBookmark() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(AppStrings.deleteConfirmTitle),
          content: const Text(AppStrings.deleteConfirmBookmark),
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
      await ref
          .read(libraryRepositoryProvider)
          .deleteBookmark(widget.bookmarkId);
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

  String _formatTimestamp(int value) {
    final DateTime dt = DateTime.fromMillisecondsSinceEpoch(value).toLocal();
    final String month = dt.month.toString().padLeft(2, '0');
    final String day = dt.day.toString().padLeft(2, '0');
    final String hour = dt.hour.toString().padLeft(2, '0');
    final String minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$month-$day $hour:$minute';
  }
}

class _BookmarkSaveIntent extends Intent {
  const _BookmarkSaveIntent();
}

class _BookmarkCancelIntent extends Intent {
  const _BookmarkCancelIntent();
}
