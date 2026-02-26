import 'dart:convert';

import '../ai/ai_provider_client.dart';
import '../ai/ai_provider_config.dart';
import '../ai/prompts.dart';
import 'local_search_service.dart';
import 'models/search_result_item.dart';

class AiSearchService {
  AiSearchService({required this.client, required this.localSearch});

  final AiProviderClient client;
  final LocalSearchService localSearch;

  Future<List<SearchResultItem>> deepSearch({
    required AiProviderConfig config,
    required String model,
    required String query,
  }) async {
    final String planText = await client.generateText(
      config: config,
      model: model,
      systemPrompt: AiPrompts.searchPlanSystemPrompt,
      userPrompt: query,
      maxTokens: 700,
    );

    final Object? decoded = jsonDecode(planText.trim());
    if (decoded is! Map<String, Object?>) {
      throw Exception('Search Plan 解析失败');
    }

    final List<Object?> rounds =
        (decoded['rounds'] as List<Object?>?) ?? <Object?>[];
    final Map<String, SearchResultItem> merged = <String, SearchResultItem>{};

    for (final Object? round in rounds.take(3)) {
      if (round is! Map<String, Object?>) {
        continue;
      }
      final List<Object?> ftsQueries =
          (round['fts_queries'] as List<Object?>?) ?? <Object?>[];
      final int topK = (round['top_k'] as int?) ?? 30;
      final Map<String, Object?> filters =
          (round['filters'] as Map<String, Object?>?) ?? <String, Object?>{};
      final List<String>? types = (filters['types'] as List<Object?>?)
          ?.whereType<String>()
          .toList(growable: false);

      for (final Object? q in ftsQueries.take(6)) {
        if (q is! String || q.trim().isEmpty) {
          continue;
        }
        final List<SearchResultItem> hits = await localSearch.search(
          query: q,
          limit: topK,
          types: types,
        );
        for (final hit in hits) {
          merged['${hit.entityType}:${hit.entityId}'] = hit;
          if (merged.length >= 50) {
            break;
          }
        }
      }
    }

    final List<SearchResultItem> candidates = merged.values.toList(
      growable: false,
    );
    if (candidates.isEmpty) {
      return candidates;
    }

    final String rerankPrompt = _buildRerankPrompt(query, candidates);
    try {
      final String rerankText = await client.generateText(
        config: config,
        model: model,
        systemPrompt: '你是重排器。只输出 JSON 数组，每项包含 entity_type, entity_id, reason。',
        userPrompt: rerankPrompt,
        maxTokens: 900,
      );

      final Object? rerankDecoded = jsonDecode(rerankText.trim());
      if (rerankDecoded is! List<Object?>) {
        return candidates;
      }

      final Map<String, SearchResultItem> map = {
        for (final item in candidates)
          '${item.entityType}:${item.entityId}': item,
      };

      final List<SearchResultItem> ranked = <SearchResultItem>[];
      for (final Object? raw in rerankDecoded) {
        if (raw is! Map<String, Object?>) {
          continue;
        }
        final String? type = raw['entity_type'] as String?;
        final String? id = raw['entity_id'] as String?;
        final String reason = (raw['reason'] as String?) ?? '';
        if (type == null || id == null) {
          continue;
        }
        final key = '$type:$id';
        final hit = map[key];
        if (hit != null) {
          ranked.add(hit.copyWith(reason: reason));
          map.remove(key);
        }
      }

      ranked.addAll(map.values);
      return ranked.take(50).toList(growable: false);
    } catch (_) {
      return candidates;
    }
  }

  String _buildRerankPrompt(String query, List<SearchResultItem> candidates) {
    final StringBuffer buffer = StringBuffer();
    buffer.writeln('用户查询: $query');
    buffer.writeln('候选:');
    for (final item in candidates) {
      buffer.writeln(
        '- ${item.entityType} | ${item.entityId} | ${item.title} | ${item.snippet}',
      );
    }
    buffer.writeln('按相关性排序并输出 JSON 数组。');
    return buffer.toString();
  }
}
