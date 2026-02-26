import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_provider_providers.dart';
import '../../core/db/app_database.dart';
import '../../core/db/db_provider.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/search/ai_search_service.dart';
import '../../core/search/local_search_service.dart';
import '../../core/search/models/search_result_item.dart';
import '../../core/utils/url_opener.dart';
import '../library/data/library_providers.dart';
import '../library/data/library_repository.dart';

final Provider<LocalSearchService> localSearchServiceProvider =
    Provider<LocalSearchService>((Ref ref) {
      final db = ref.watch(appDatabaseProvider).requireValue;
      return LocalSearchService(db);
    });

final Provider<AiSearchService> aiSearchServiceProvider =
    Provider<AiSearchService>((Ref ref) {
      return AiSearchService(
        client: ref.watch(aiProviderClientProvider),
        localSearch: ref.watch(localSearchServiceProvider),
      );
    });

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  static const Set<String> _allTypes = <String>{'todo', 'note', 'bookmark'};

  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();

  bool _searching = false;
  bool _deepMode = true;
  String _status = '';
  String _planningStatus = '-';
  String _retrievingStatus = '-';
  String _rerankingStatus = '-';
  bool _stageExpanded = true;

  final Set<String> _selectedTypes = <String>{'todo', 'note', 'bookmark'};
  List<SearchResultItem> _results = const <SearchResultItem>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _inputFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String keyword = _controller.text.trim();
    final Map<String, List<SearchResultItem>> grouped =
        <String, List<SearchResultItem>>{};
    for (final SearchResultItem item in _results) {
      grouped
          .putIfAbsent(item.entityType, () => <SearchResultItem>[])
          .add(item);
    }

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.search)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              focusNode: _inputFocusNode,
              controller: _controller,
              decoration: InputDecoration(
                hintText: AppStrings.localSearchHint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.search),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _runPrimarySearch(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton(
                  onPressed: _searching ? null : _runLocalSearch,
                  child: const Text(AppStrings.localSearch),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _searching ? null : _runAiSearch,
                  child: const Text(AppStrings.aiSearch),
                ),
                const SizedBox(width: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: true,
                      label: Text(AppStrings.searchModeDeep),
                    ),
                    ButtonSegment<bool>(
                      value: false,
                      label: Text(AppStrings.searchModeNormal),
                    ),
                  ],
                  selected: <bool>{_deepMode},
                  onSelectionChanged: (Set<bool> values) {
                    setState(() {
                      _deepMode = values.first;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                AppStrings.searchCostHint,
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                AppStrings.searchFilterTitle,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _typeChip('todo', AppStrings.todoTab),
                _typeChip('note', AppStrings.noteTab),
                _typeChip('bookmark', AppStrings.bookmarkTab),
              ],
            ),
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: Text(_status)),
            ],
            if (_shouldShowStagePanel) ...[
              const SizedBox(height: 8),
              _buildStagePanel(),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: _results.isEmpty
                  ? _searching
                        ? const _SearchSkeletonList()
                        : const Center(child: Text(AppStrings.searchNoResult))
                  : ListView(
                      children: [
                        for (final MapEntry<String, List<SearchResultItem>>
                            entry
                            in grouped.entries) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 4),
                            child: Text(
                              _entityTypeLabel(entry.key),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          for (final SearchResultItem item in entry.value)
                            _SearchResultTile(
                              item: item,
                              keyword: keyword,
                              onTap: () => _openResultDetail(item),
                              onCopyReason: item.reason.isEmpty
                                  ? null
                                  : () => _copyReason(item),
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _shouldShowStagePanel =>
      _searching ||
      _planningStatus != '-' ||
      _retrievingStatus != '-' ||
      _rerankingStatus != '-';

  Widget _typeChip(String type, String label) {
    final bool selected = _selectedTypes.contains(type);
    return FilterChip(
      selected: selected,
      label: Text(label),
      onSelected: (bool value) {
        setState(() {
          if (value) {
            _selectedTypes.add(type);
          } else {
            _selectedTypes.remove(type);
          }
        });
      },
    );
  }

  Widget _buildStagePanel() {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: _stageExpanded,
        onExpansionChanged: (bool expanded) {
          setState(() {
            _stageExpanded = expanded;
          });
        },
        title: const Text(AppStrings.searchStageTitle),
        children: [
          _stageLine(AppStrings.searchStagePlanning, _planningStatus),
          _stageLine(AppStrings.searchStageRetrieving, _retrievingStatus),
          _stageLine(AppStrings.searchStageReranking, _rerankingStatus),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _stageLine(String stage, String value) {
    return ListTile(dense: true, title: Text(stage), trailing: Text(value));
  }

  Future<void> _runPrimarySearch() async {
    if (_deepMode) {
      await _runAiSearch();
    } else {
      await _runLocalSearch();
    }
  }

  Future<void> _runLocalSearch() async {
    if (_searching) {
      return;
    }
    final String query = _controller.text.trim();
    if (query.isEmpty) {
      return;
    }

    setState(() {
      _searching = true;
      _status = '';
      _planningStatus = '-';
      _retrievingStatus = '-';
      _rerankingStatus = '-';
    });

    try {
      final List<SearchResultItem> items = await ref
          .read(localSearchServiceProvider)
          .search(query: query, types: _normalizedTypes);
      if (!mounted) {
        return;
      }
      setState(() {
        _results = items;
        _status = '${AppStrings.searchLocalDonePrefix}${items.length} 条';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = '${AppStrings.searchLocalFailPrefix}$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _searching = false;
        });
      }
    }
  }

  Future<void> _runAiSearch() async {
    if (_searching) {
      return;
    }
    final String query = _controller.text.trim();
    if (query.isEmpty) {
      return;
    }

    if (!_deepMode) {
      await _runLocalSearch();
      return;
    }

    setState(() {
      _searching = true;
      _status = '';
      _planningStatus = '等待';
      _retrievingStatus = '等待';
      _rerankingStatus = '等待';
      _stageExpanded = true;
    });

    try {
      final cfg = await ref.read(aiProviderRepositoryProvider).load();
      if (!cfg.isReady || cfg.selectedModel.trim().isEmpty) {
        throw Exception(AppStrings.inboxNeedModel);
      }

      final AiSearchResponse response = await ref
          .read(aiSearchServiceProvider)
          .deepSearchWithMeta(
            config: cfg,
            model: cfg.selectedModel,
            query: query,
            types: _normalizedTypes,
            onStage: (AiSearchStage stage, String message) {
              if (!mounted) {
                return;
              }
              setState(() {
                switch (stage) {
                  case AiSearchStage.planning:
                    _planningStatus = message;
                    break;
                  case AiSearchStage.retrieving:
                    _retrievingStatus = message;
                    break;
                  case AiSearchStage.reranking:
                    _rerankingStatus = message;
                    break;
                }
              });
            },
          );

      if (!mounted) {
        return;
      }
      setState(() {
        _results = response.items;
        if (response.degradedToLocal) {
          _status = '${AppStrings.searchFallbackPrefix}${response.message}';
          _rerankingStatus = '已跳过';
        } else {
          _status =
              '${AppStrings.searchAiDonePrefix}${response.items.length} 条';
          _planningStatus = '完成';
          _retrievingStatus = '完成';
          _rerankingStatus = '完成';
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = '${AppStrings.searchAiFailPrefix}$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _searching = false;
        });
      }
    }
  }

  Future<void> _openResultDetail(SearchResultItem item) async {
    final LibraryRepository repository = ref.read(libraryRepositoryProvider);
    switch (item.entityType) {
      case 'todo':
        final TodoDetail? detail = await repository.getTodoDetail(
          item.entityId,
        );
        if (detail == null || !mounted) {
          return;
        }
        await showDialog<void>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Todo: ${detail.title}'),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${AppStrings.fieldPriority}: ${_priorityLabel(detail.priority)}',
                    ),
                    Text(
                      '${AppStrings.fieldStatus}: ${detail.status == TodoStatusCode.done ? AppStrings.statusDone : AppStrings.statusOpen}',
                    ),
                    Text(
                      '${AppStrings.fieldRemindAt}: ${detail.remindAt == null ? '未设置' : _fmt(detail.remindAt!)}',
                    ),
                    const SizedBox(height: 8),
                    Text('标签: ${detail.tags.join(', ')}'),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(AppStrings.confirm),
                ),
              ],
            );
          },
        );
      case 'note':
        final NoteDetail? detail = await repository.getNoteDetail(
          item.entityId,
        );
        if (detail == null || !mounted) {
          return;
        }
        bool showRaw = false;
        await showDialog<void>(
          context: context,
          builder: (BuildContext context) {
            return StatefulBuilder(
              builder: (BuildContext context, StateSetter setStateDialog) {
                return AlertDialog(
                  title: Text(
                    '${AppStrings.noteDetailTitle} v${detail.latestVersion}',
                  ),
                  content: SizedBox(
                    width: 640,
                    child: SingleChildScrollView(
                      child: SelectableText(
                        showRaw ? detail.rawText : detail.organizedMd,
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        setStateDialog(() {
                          showRaw = !showRaw;
                        });
                      },
                      child: Text(
                        showRaw
                            ? AppStrings.noteViewOrganized
                            : AppStrings.noteViewRaw,
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(AppStrings.confirm),
                    ),
                  ],
                );
              },
            );
          },
        );
      case 'bookmark':
        final BookmarkDetail? detail = await repository.getBookmarkDetail(
          item.entityId,
        );
        if (detail == null || !mounted) {
          return;
        }
        await showDialog<void>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text(detail.title),
              content: SizedBox(
                width: 620,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(detail.url),
                    const SizedBox(height: 8),
                    Text(
                      '${AppStrings.bookmarkLastFetchedAt}: ${detail.lastFetchedAt == null ? AppStrings.bookmarkNotFetched : _fmt(detail.lastFetchedAt!)}',
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: detail.url));
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text(AppStrings.copied)),
                    );
                  },
                  child: const Text(AppStrings.bookmarkCopyUrl),
                ),
                TextButton(
                  onPressed: () async {
                    await UrlOpener.open(detail.url);
                  },
                  child: const Text(AppStrings.bookmarkOpenUrl),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(AppStrings.confirm),
                ),
              ],
            );
          },
        );
      default:
        return;
    }
  }

  Future<void> _copyReason(SearchResultItem item) async {
    final String payload =
        '${AppStrings.searchHitReasonPrefix}${item.reason}\n'
        'entity://${item.entityType}/${item.entityId}\n'
        '${item.title}';
    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(AppStrings.searchCopiedReason)),
    );
  }

  List<String>? get _normalizedTypes {
    if (_selectedTypes.isEmpty || _selectedTypes.length == _allTypes.length) {
      return null;
    }
    return _selectedTypes.toList(growable: false);
  }

  String _entityTypeLabel(String type) {
    switch (type) {
      case 'todo':
        return AppStrings.todoTab;
      case 'note':
        return AppStrings.noteTab;
      case 'bookmark':
        return AppStrings.bookmarkTab;
      default:
        return type;
    }
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

  String _fmt(int value) {
    final DateTime dt = DateTime.fromMillisecondsSinceEpoch(value).toLocal();
    return dt.toString();
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.item,
    required this.keyword,
    required this.onTap,
    required this.onCopyReason,
  });

  final SearchResultItem item;
  final String keyword;
  final VoidCallback onTap;
  final VoidCallback? onCopyReason;

  @override
  Widget build(BuildContext context) {
    final TextStyle titleStyle =
        Theme.of(context).textTheme.bodyLarge ??
        const TextStyle(fontSize: 16, fontWeight: FontWeight.w500);
    final TextStyle subtitleStyle =
        Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 13);
    final String snippet = _truncate(item.snippet.replaceAll('\n', ' ').trim());

    return ListTile(
      dense: true,
      onTap: onTap,
      title: RichText(
        text: _highlightKeyword(
          text: item.title,
          keyword: keyword,
          baseStyle: titleStyle,
          highlightStyle: titleStyle.copyWith(
            backgroundColor: Colors.amber.withValues(alpha: 0.35),
          ),
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: _highlightSnippet(
              snippet: snippet,
              keyword: keyword,
              baseStyle: subtitleStyle,
            ),
          ),
          if (item.reason.isNotEmpty)
            Text(
              '${AppStrings.searchHitReasonPrefix}${item.reason}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      trailing: onCopyReason == null
          ? null
          : IconButton(
              icon: const Icon(Icons.copy_all_outlined),
              tooltip: AppStrings.searchCopyReason,
              onPressed: onCopyReason,
            ),
    );
  }

  String _truncate(String text) {
    if (text.length <= 140) {
      return text;
    }
    return '${text.substring(0, 140)}...';
  }

  TextSpan _highlightSnippet({
    required String snippet,
    required String keyword,
    required TextStyle baseStyle,
  }) {
    if (snippet.contains('[') && snippet.contains(']')) {
      final List<InlineSpan> spans = <InlineSpan>[];
      final RegExp reg = RegExp(r'\\[(.*?)\\]');
      int start = 0;
      for (final RegExpMatch m in reg.allMatches(snippet)) {
        if (m.start > start) {
          spans.add(TextSpan(text: snippet.substring(start, m.start)));
        }
        spans.add(
          TextSpan(
            text: m.group(1),
            style: baseStyle.copyWith(
              backgroundColor: Colors.amber.withValues(alpha: 0.35),
            ),
          ),
        );
        start = m.end;
      }
      if (start < snippet.length) {
        spans.add(TextSpan(text: snippet.substring(start)));
      }
      return TextSpan(style: baseStyle, children: spans);
    }
    return _highlightKeyword(
      text: snippet,
      keyword: keyword,
      baseStyle: baseStyle,
      highlightStyle: baseStyle.copyWith(
        backgroundColor: Colors.amber.withValues(alpha: 0.35),
      ),
    );
  }

  TextSpan _highlightKeyword({
    required String text,
    required String keyword,
    required TextStyle baseStyle,
    required TextStyle highlightStyle,
  }) {
    final String key = keyword.trim();
    if (key.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }
    final String lowerText = text.toLowerCase();
    final String lowerKey = key.toLowerCase();
    int start = 0;
    final List<InlineSpan> spans = <InlineSpan>[];
    while (true) {
      final int index = lowerText.indexOf(lowerKey, start);
      if (index < 0) {
        if (start < text.length) {
          spans.add(TextSpan(text: text.substring(start), style: baseStyle));
        }
        break;
      }
      if (index > start) {
        spans.add(
          TextSpan(text: text.substring(start, index), style: baseStyle),
        );
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + key.length),
          style: highlightStyle,
        ),
      );
      start = index + key.length;
    }
    return TextSpan(children: spans, style: baseStyle);
  }
}

class _SearchSkeletonList extends StatelessWidget {
  const _SearchSkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 6,
      itemBuilder: (BuildContext context, int index) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 14,
                width: 180 + (index % 3) * 80,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 12,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
