import 'dart:convert';

import 'ai_provider_client.dart';
import 'ai_provider_config.dart';
import 'prompts.dart';
import 'router_decision.dart';
import 'router_schema_validator.dart';

class RouterService {
  RouterService({required this.client, required this.validator});

  final AiProviderClient client;
  final RouterSchemaValidator validator;

  Future<RouterDecision> route({
    required AiProviderConfig config,
    required String model,
    required String userInput,
  }) async {
    final String responseText = await client.generateText(
      config: config,
      model: model,
      systemPrompt: AiPrompts.routerSystemPrompt,
      userPrompt: userInput,
      maxTokens: 400,
    );

    final Object? decoded = jsonDecode(responseText.trim());
    final RouterValidationResult result = validator.validate(decoded);
    if (!result.isValid) {
      throw Exception('Router 输出校验失败：${result.error}');
    }

    return RouterDecision.fromJson(decoded as Map<String, Object?>);
  }
}
