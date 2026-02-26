import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_provider_config.dart';

class ModelProbeResult {
  const ModelProbeResult({
    required this.model,
    required this.success,
    required this.elapsedMs,
    required this.error,
  });

  final String model;
  final bool success;
  final int elapsedMs;
  final String error;
}

class AiProviderClient {
  const AiProviderClient();

  Future<List<String>> fetchModels(AiProviderConfig config) async {
    final Uri uri = Uri.parse('${config.apiRoot}/models');
    final http.Response response = await http.get(
      uri,
      headers: _headers(config.apiKey),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('模型列表请求失败：HTTP ${response.statusCode}');
    }

    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw Exception('模型列表返回格式不正确');
    }

    final List<Object?> data =
        (decoded['data'] as List<Object?>?) ?? <Object?>[];
    final List<String> models = <String>[];
    for (final Object? item in data) {
      if (item is Map<String, Object?>) {
        final String? id = item['id'] as String?;
        if (id != null && id.isNotEmpty) {
          models.add(id);
        }
      }
    }
    return models;
  }

  Future<ModelProbeResult> probeModel(
    AiProviderConfig config,
    String model,
  ) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      final String text = await generateText(
        config: config,
        model: model,
        systemPrompt: 'You are a test probe. Reply with exactly: OK',
        userPrompt: 'ping',
        maxTokens: 3,
      );
      stopwatch.stop();

      if (text.trim().isEmpty) {
        return ModelProbeResult(
          model: model,
          success: false,
          elapsedMs: stopwatch.elapsedMilliseconds,
          error: '返回文本为空',
        );
      }

      return ModelProbeResult(
        model: model,
        success: true,
        elapsedMs: stopwatch.elapsedMilliseconds,
        error: '',
      );
    } catch (error) {
      stopwatch.stop();
      return ModelProbeResult(
        model: model,
        success: false,
        elapsedMs: stopwatch.elapsedMilliseconds,
        error: error.toString(),
      );
    }
  }

  Future<String> generateText({
    required AiProviderConfig config,
    required String model,
    required String systemPrompt,
    required String userPrompt,
    int maxTokens = 256,
  }) async {
    try {
      return await _chatCompletion(
        config: config,
        model: model,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        maxTokens: maxTokens,
      );
    } catch (chatError) {
      if (!chatError.toString().contains('HTTP 404')) {
        rethrow;
      }
      return _completions(
        config: config,
        model: model,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        maxTokens: maxTokens,
      );
    }
  }

  Future<String> _chatCompletion({
    required AiProviderConfig config,
    required String model,
    required String systemPrompt,
    required String userPrompt,
    required int maxTokens,
  }) async {
    final Uri uri = Uri.parse('${config.apiRoot}/chat/completions');
    final http.Response response = await http.post(
      uri,
      headers: _headers(config.apiKey),
      body: jsonEncode(<String, Object?>{
        'model': model,
        'messages': <Map<String, String>>[
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        'max_tokens': maxTokens,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('chat completion failed: HTTP ${response.statusCode}');
    }

    final Object? decoded = jsonDecode(response.body);
    final String text = _extractAssistantText(decoded);
    if (text.trim().isEmpty) {
      throw Exception('chat completion 返回文本为空');
    }
    return text;
  }

  Future<String> _completions({
    required AiProviderConfig config,
    required String model,
    required String systemPrompt,
    required String userPrompt,
    required int maxTokens,
  }) async {
    final Uri uri = Uri.parse('${config.apiRoot}/completions');
    final http.Response response = await http.post(
      uri,
      headers: _headers(config.apiKey),
      body: jsonEncode(<String, Object?>{
        'model': model,
        'prompt': '$systemPrompt\n\n$userPrompt',
        'max_tokens': maxTokens,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('completions failed: HTTP ${response.statusCode}');
    }

    final Object? decoded = jsonDecode(response.body);
    final String text = _extractCompletionText(decoded);
    if (text.trim().isEmpty) {
      throw Exception('completions 返回文本为空');
    }
    return text;
  }

  Map<String, String> _headers(String apiKey) => <String, String>{
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $apiKey',
  };

  String _extractAssistantText(Object? json) {
    if (json is! Map<String, Object?>) {
      return '';
    }
    final List<Object?> choices =
        (json['choices'] as List<Object?>?) ?? <Object?>[];
    if (choices.isEmpty || choices.first is! Map<String, Object?>) {
      return '';
    }

    final Map<String, Object?> choice = choices.first as Map<String, Object?>;
    final Object? message = choice['message'];
    if (message is Map<String, Object?>) {
      return (message['content'] as String?) ?? '';
    }
    return '';
  }

  String _extractCompletionText(Object? json) {
    if (json is! Map<String, Object?>) {
      return '';
    }

    final List<Object?> choices =
        (json['choices'] as List<Object?>?) ?? <Object?>[];
    if (choices.isEmpty || choices.first is! Map<String, Object?>) {
      return '';
    }

    final Map<String, Object?> choice = choices.first as Map<String, Object?>;
    return (choice['text'] as String?) ?? '';
  }
}
