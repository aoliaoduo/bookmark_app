import 'dart:convert';

import '../ai/ai_provider_client.dart';
import '../ai/ai_provider_config.dart';
import '../ai/prompts.dart';
import 'local_search_service.dart';
import 'models/search_result_item.dart';

enum AiSearchStage { planning, retrieving, reranking }

class AiSearchResponse {
  const AiSearchResponse({
    required this.items,
    required this.degradedToLocal,
    required this.message,
  });

  final List<SearchResultItem> items;
  final bool degradedToLocal;
  final String message;
}

class AiSearchService {
  AiSearchService({required this.client, required this.localSearch});

  final AiProviderClient client;
  final LocalSearchService localSearch;

  Future<List<SearchResultItem>> deepSearch({
    required AiProviderConfig config,
    required String model,
    required String query,
    List<String>? types,
  }) async {
    final AiSearchResponse response = await deepSearchWithMeta(
      config: config,
      model: model,
      query: query,
      types: types,
    );
    return response.items;
  }

  Future<AiSearchResponse> deepSearchWithMeta({
    required AiProviderConfig config,
    required String model,
    required String query,
    List<String>? types,
    void Function(AiSearchStage stage, String message)? onStage,
  }) async {
    try {
      onStage?.call(AiSearchStage.planning, '正在规划');
      final String planText = await client.generateText(
        config: config,
        model: model,
        systemPrompt: AiPrompts.searchPlanSystemPrompt,
        userPrompt: query,
        maxTokens: 700,
      );
      final List<_SearchRound> rounds = _parsePlan(planText);

      onStage?.call(AiSearchStage.retrieving, '正在检索');
      final Map<String, SearchResultItem> merged = <String, SearchResultItem>{};
      for (final _SearchRound round in rounds.take(3)) {
        final List<String> finalTypes = _mergeTypes(round.types, types);
        for (final String q in round.ftsQueries.take(6)) {
          final List<SearchResultItem> hits = await localSearch.search(
            query: q,
            limit: round.topK,
            types: finalTypes.isEmpty ? null : finalTypes,
          );
          for (final SearchResultItem hit in hits) {
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
        return const AiSearchResponse(
          items: <SearchResultItem>[],
          degradedToLocal: false,
          message: '',
        );
      }

      onStage?.call(AiSearchStage.reranking, '正在重排');
      final List<SearchResultItem> ranked = await _rerank(
        config: config,
        model: model,
        query: query,
        candidates: candidates,
      );

      return AiSearchResponse(
        items: ranked,
        degradedToLocal: false,
        message: '',
      );
    } catch (error) {
      final List<SearchResultItem> localFallback = await localSearch.search(
        query: query,
        limit: 50,
        types: types,
      );
      return AiSearchResponse(
        items: localFallback,
        degradedToLocal: true,
        message: error.toString(),
      );
    }
  }

  List<_SearchRound> _parsePlan(String planText) {
    final Object? decoded = jsonDecode(planText.trim());
    if (decoded is! Map<String, Object?>) {
      throw Exception('Search Plan 解析失败');
    }

    final List<Object?> roundsRaw =
        (decoded['rounds'] as List<Object?>?) ?? <Object?>[];
    if (roundsRaw.isEmpty) {
      throw Exception('Search Plan 缺少 rounds');
    }

    final List<_SearchRound> rounds = <_SearchRound>[];
    for (final Object? raw in roundsRaw) {
      if (raw is! Map<String, Object?>) {
        continue;
      }
      final List<String> queries =
          ((raw['fts_queries'] as List<Object?>?) ?? <Object?>[])
              .whereType<String>()
              .map((String v) => v.trim())
              .where((String v) => v.isNotEmpty)
              .toList(growable: false);
      if (queries.isEmpty) {
        continue;
      }
      final int topK = ((raw['top_k'] as num?)?.toInt() ?? 30).clamp(1, 80);
      final Map<String, Object?> filters =
          (raw['filters'] as Map<String, Object?>?) ?? <String, Object?>{};
      final List<String> types =
          ((filters['types'] as List<Object?>?) ?? <Object?>[])
              .whereType<String>()
              .where((String t) => _allowedEntityTypes.contains(t))
              .toList(growable: false);
      rounds.add(_SearchRound(ftsQueries: queries, topK: topK, types: types));
    }
    if (rounds.isEmpty) {
      throw Exception('Search Plan schema 校验失败');
    }
    return rounds;
  }

  List<String> _mergeTypes(List<String> fromPlan, List<String>? fromUi) {
    final Set<String> merged = <String>{};
    if (fromPlan.isNotEmpty) {
      merged.addAll(fromPlan.where(_allowedEntityTypes.contains));
    }
    if (fromUi != null && fromUi.isNotEmpty) {
      if (merged.isEmpty) {
        merged.addAll(fromUi.where(_allowedEntityTypes.contains));
      } else {
        merged.removeWhere((String t) => !fromUi.contains(t));
      }
    }
    return merged.toList(growable: false);
  }

  Future<List<SearchResultItem>> _rerank({
    required AiProviderConfig config,
    required String model,
    required String query,
    required List<SearchResultItem> candidates,
  }) async {
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
        for (final SearchResultItem item in candidates)
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
        final String key = '$type:$id';
        final SearchResultItem? hit = map[key];
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
    for (final SearchResultItem item in candidates) {
      buffer.writeln(
        '- ${item.entityType} | ${item.entityId} | ${item.title} | ${item.snippet}',
      );
    }
    buffer.writeln('按相关性排序并输出 JSON 数组。');
    return buffer.toString();
  }
}

class _SearchRound {
  const _SearchRound({
    required this.ftsQueries,
    required this.topK,
    required this.types,
  });

  final List<String> ftsQueries;
  final int topK;
  final List<String> types;
}

const Set<String> _allowedEntityTypes = <String>{'todo', 'note', 'bookmark'};
