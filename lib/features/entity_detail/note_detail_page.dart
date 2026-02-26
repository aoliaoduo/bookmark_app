import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_provider_providers.dart';
import '../../core/ai/ai_provider_repository.dart';
import '../../core/i18n/app_strings.dart';
import '../library/data/library_providers.dart';
import '../library/data/library_repository.dart';

class NoteDetailPage extends ConsumerStatefulWidget {
  const NoteDetailPage({super.key, required this.noteId});

  final String noteId;

  @override
  ConsumerState<NoteDetailPage> createState() => _NoteDetailPageState();
}

class _NoteDetailPageState extends ConsumerState<NoteDetailPage> {
  NoteDetail? _detail;
  List<NoteVersionItem> _versions = const <NoteVersionItem>[];

  bool _loading = true;
  bool _editing = false;
  bool _saving = false;
  bool _showRaw = false;
  bool _loadingVersion = false;
  bool _regenerating = false;
  bool _cancelRegenerateRequested = false;
  bool _dirty = false;

  int _selectedVersion = 1;
  String _displayMd = '';

  late final TextEditingController _titleController;
  late final TextEditingController _tagsController;
  late final TextEditingController _preferenceController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _tagsController = TextEditingController();
    _preferenceController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _tagsController.dispose();
    _preferenceController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final LibraryRepository repository = ref.read(libraryRepositoryProvider);
    final NoteDetail? detail = await repository.getNoteDetail(widget.noteId);
    final List<NoteVersionItem> versions = await repository.listNoteVersions(
      widget.noteId,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _detail = detail;
      _versions = versions;
      _loading = false;
      if (detail != null) {
        _selectedVersion = detail.latestVersion;
        _displayMd = detail.organizedMd;
        _titleController.text = detail.title;
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
              _NoteSaveIntent(),
          SingleActivator(LogicalKeyboardKey.escape): _NoteCancelIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _NoteSaveIntent: CallbackAction<_NoteSaveIntent>(
              onInvoke: (_NoteSaveIntent intent) {
                if (_editing) {
                  _saveMetaChanges();
                }
                return null;
              },
            ),
            _NoteCancelIntent: CallbackAction<_NoteCancelIntent>(
              onInvoke: (_NoteCancelIntent intent) {
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
                title: Text(
                  '${AppStrings.noteDetailTitle}${_detail == null ? '' : ' v$_selectedVersion'}',
                ),
                actions: _buildActions(),
              ),
              body: _buildBody(context),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActions() {
    final NoteDetail? detail = _detail;
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
            onPressed: _saving ? null : _saveMetaChanges,
            child: Text(_saving ? '${AppStrings.save}...' : AppStrings.save),
          ),
        ),
      ];
    }

    return <Widget>[
      IconButton(
        tooltip: AppStrings.noteViewRaw,
        onPressed: () {
          setState(() {
            _showRaw = !_showRaw;
          });
        },
        icon: Icon(
          _showRaw ? Icons.article_outlined : Icons.description_outlined,
        ),
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
      const SizedBox(width: 4),
    ];
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final NoteDetail? detail = _detail;
    if (detail == null) {
      return const Center(child: Text(AppStrings.detailLoadFailed));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_editing) _buildEditMeta(),
          if (_editing) const SizedBox(height: 12),
          if (!_editing) ...[
            Text(detail.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('${AppStrings.fieldTags}: ${detail.tags.join(', ')}'),
            const SizedBox(height: 12),
          ],
          const Text(AppStrings.noteVersionList),
          const SizedBox(height: 6),
          if (_versions.isEmpty)
            const Text(AppStrings.noteVersionNoHistory)
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final NoteVersionItem item in _versions)
                  ChoiceChip(
                    label: Text('v${item.version}'),
                    selected: _selectedVersion == item.version,
                    onSelected: (_) => _loadVersion(item.version),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _showRaw = !_showRaw;
                  });
                },
                child: Text(
                  _showRaw
                      ? AppStrings.noteViewOrganized
                      : AppStrings.noteViewRaw,
                ),
              ),
              OutlinedButton(
                onPressed: _regenerating ? null : _regenerate,
                child: Text(
                  _regenerating
                      ? AppStrings.noteRegenerating
                      : AppStrings.noteReorganize,
                ),
              ),
              OutlinedButton(
                onPressed: _regenerating ? null : () => _pruneVersions(5),
                child: const Text(AppStrings.noteVersionKeepLatestFive),
              ),
              OutlinedButton(
                onPressed: _regenerating ? null : () => _pruneVersions(1),
                child: const Text(AppStrings.noteVersionKeepLatestOne),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _preferenceController,
            enabled: !_regenerating,
            decoration: const InputDecoration(
              labelText: AppStrings.notePreferenceHint,
            ),
            textInputAction: TextInputAction.done,
          ),
          if (_regenerating) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () {
                setState(() {
                  _cancelRegenerateRequested = true;
                });
              },
              child: const Text(AppStrings.noteCancelRegenerate),
            ),
          ],
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 360,
              child: _loadingVersion
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        _showRaw ? detail.rawText : _displayMd,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditMeta() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(labelText: AppStrings.fieldTitle),
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

  Future<void> _loadVersion(int version) async {
    if (_loadingVersion || version == _selectedVersion) {
      return;
    }
    setState(() {
      _loadingVersion = true;
    });
    final String? content = await ref
        .read(libraryRepositoryProvider)
        .getNoteVersionContent(noteId: widget.noteId, version: version);
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedVersion = version;
      _displayMd = content ?? '';
      _showRaw = false;
      _loadingVersion = false;
    });
  }

  Future<void> _pruneVersions(int keepLatest) async {
    try {
      await ref
          .read(libraryRepositoryProvider)
          .pruneNoteVersions(noteId: widget.noteId, keepLatest: keepLatest);
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
    }
  }

  Future<void> _regenerate() async {
    if (_regenerating) {
      return;
    }

    final NoteDetail? detail = _detail;
    if (detail == null) {
      return;
    }

    setState(() {
      _regenerating = true;
      _cancelRegenerateRequested = false;
    });

    try {
      final AiProviderRepository providerRepo = ref.read(
        aiProviderRepositoryProvider,
      );
      final cfg = await providerRepo.load();
      if (!cfg.isReady || cfg.selectedModel.trim().isEmpty) {
        throw Exception(AppStrings.inboxNeedModel);
      }

      final String preference = _preferenceController.text.trim();
      final String prompt = preference.isEmpty
          ? 'You are a note organizer. Output Markdown only. Do not output code fences.'
          : 'You are a note organizer. Output Markdown only. Do not output code fences. User preference: $preference';

      final String newMd = await ref
          .read(aiProviderClientProvider)
          .generateText(
            config: cfg,
            model: cfg.selectedModel,
            systemPrompt: prompt,
            userPrompt: detail.rawText,
            maxTokens: 1500,
          );

      if (_cancelRegenerateRequested) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(AppStrings.noteRegenerateCancelled)),
          );
        }
        return;
      }

      await ref
          .read(libraryRepositoryProvider)
          .appendNoteVersion(
            noteId: widget.noteId,
            organizedMd: _stripMarkdownFences(newMd),
            keepLatest: 5,
          );
      _dirty = true;
      await _load();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.noteVersionSaved)),
      );
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
          _regenerating = false;
        });
      }
    }
  }

  Future<void> _saveMetaChanges() async {
    if (_saving) {
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
          .updateNoteDetail(
            noteId: widget.noteId,
            title: title,
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
    final NoteDetail? detail = _detail;
    if (detail != null) {
      _titleController.text = detail.title;
      _tagsController.text = detail.tags.join(', ');
    }
    setState(() {
      _editing = false;
    });
  }

  List<String> _parseTags(String input) {
    return input
        .split(',')
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  String _stripMarkdownFences(String input) {
    final String trimmed = input.trim();
    final List<String> lines = trimmed.split('\n');
    if (lines.length >= 2 &&
        lines.first.trimLeft().startsWith('```') &&
        lines.last.trim() == '```') {
      return lines.sublist(1, lines.length - 1).join('\n').trim();
    }
    return trimmed
        .replaceAll('```markdown', '')
        .replaceAll('```md', '')
        .replaceAll('```', '')
        .trim();
  }
}

class _NoteSaveIntent extends Intent {
  const _NoteSaveIntent();
}

class _NoteCancelIntent extends Intent {
  const _NoteCancelIntent();
}
