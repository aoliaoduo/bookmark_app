import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_provider_providers.dart';
import '../../core/db/db_provider.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/search/ai_search_service.dart';
import '../../core/search/local_search_service.dart';
import '../../core/search/models/search_result_item.dart';

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
  final TextEditingController _controller = TextEditingController();

  bool _searching = false;
  String _status = '';
  List<SearchResultItem> _results = const <SearchResultItem>[];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<SearchResultItem>>{};
    for (final item in _results) {
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
              controller: _controller,
              decoration: InputDecoration(
                hintText: AppStrings.localSearchHint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: (_) => _runLocalSearch(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton(
                  onPressed: _searching ? null : _runLocalSearch,
                  child: const Text(AppStrings.localSearch),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _searching ? null : _runAiDeepSearch,
                  child: const Text(AppStrings.aiDeepSearch),
                ),
              ],
            ),
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: Text(_status)),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: _results.isEmpty
                  ? const Center(child: Text(AppStrings.searchNoResult))
                  : ListView(
                      children: [
                        for (final entry in grouped.entries) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 4),
                            child: Text(
                              entry.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          for (final item in entry.value)
                            ListTile(
                              dense: true,
                              title: Text(item.title),
                              subtitle: Text(
                                item.reason.isNotEmpty
                                    ? '${item.snippet}\n命中理由：${item.reason}'
                                    : item.snippet,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
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

  Future<void> _runLocalSearch() async {
    final String query = _controller.text.trim();
    if (query.isEmpty) {
      return;
    }

    setState(() {
      _searching = true;
      _status = '';
    });

    final List<SearchResultItem> items = await ref
        .read(localSearchServiceProvider)
        .search(query: query);

    if (!mounted) {
      return;
    }
    setState(() {
      _results = items;
      _searching = false;
      _status = '本地搜索完成：${items.length} 条';
    });
  }

  Future<void> _runAiDeepSearch() async {
    final String query = _controller.text.trim();
    if (query.isEmpty) {
      return;
    }

    setState(() {
      _searching = true;
      _status = '';
    });

    try {
      final cfg = await ref.read(aiProviderRepositoryProvider).load();
      if (!cfg.isReady || cfg.selectedModel.trim().isEmpty) {
        throw Exception(AppStrings.inboxNeedModel);
      }

      final List<SearchResultItem> items = await ref
          .read(aiSearchServiceProvider)
          .deepSearch(config: cfg, model: cfg.selectedModel, query: query);

      if (!mounted) {
        return;
      }

      setState(() {
        _results = items;
        _status = 'AI 深度搜索完成：${items.length} 条';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'AI 深度搜索失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _searching = false;
        });
      }
    }
  }
}
