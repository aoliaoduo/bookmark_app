import 'dart:io';

import 'package:code/core/ai/ai_provider_client.dart';
import 'package:code/core/ai/ai_provider_config.dart';
import 'package:code/core/db/app_database.dart';
import 'package:code/core/search/ai_search_service.dart';
import 'package:code/core/search/local_search_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _AlwaysFailClient extends AiProviderClient {
  const _AlwaysFailClient();

  @override
  Future<String> generateText({
    required AiProviderConfig config,
    required String model,
    required String systemPrompt,
    required String userPrompt,
    int maxTokens = 256,
  }) async {
    throw Exception('mock ai failure');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('deep_fallback_test', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'ai_deep_fallback_',
    );
    final String dbPath = p.join(tempDir.path, 'fallback.db');
    final AppDatabase appDatabase = await AppDatabase.open(
      databasePath: dbPath,
    );

    await appDatabase.db.insert('search_fts', <String, Object?>{
      'entity_type': 'todo',
      'entity_id': 'todo_1',
      'title': 'fallback todo',
      'body': 'fallback body',
      'tags': 'test',
    });

    final List<Map<String, Object?>> beforeDraftRows = await appDatabase.db
        .rawQuery('SELECT COUNT(*) AS c FROM inbox_drafts');
    final int beforeDraftCount =
        (beforeDraftRows.first['c'] as num?)?.toInt() ?? 0;

    final AiSearchService service = AiSearchService(
      client: const _AlwaysFailClient(),
      localSearch: LocalSearchService(appDatabase),
    );

    final AiSearchResponse response = await service.deepSearchWithMeta(
      config: const AiProviderConfig(
        baseUrl: 'https://example.com',
        apiRoot: 'https://example.com/v1',
        apiKey: 'k',
        selectedModel: 'm',
        storedRiskConfirmed: true,
      ),
      model: 'm',
      query: 'fallback',
      types: const <String>['todo'],
    );

    expect(response.degradedToLocal, isTrue);
    expect(response.items, isNotEmpty);
    expect(response.items.first.entityId, 'todo_1');

    final List<Map<String, Object?>> afterDraftRows = await appDatabase.db
        .rawQuery('SELECT COUNT(*) AS c FROM inbox_drafts');
    final int afterDraftCount =
        (afterDraftRows.first['c'] as num?)?.toInt() ?? 0;
    expect(afterDraftCount, beforeDraftCount);

    await appDatabase.close();
    await tempDir.delete(recursive: true);
  });
}
