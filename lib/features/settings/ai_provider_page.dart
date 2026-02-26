import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_provider_client.dart';
import '../../core/ai/ai_provider_config.dart';
import '../../core/ai/ai_provider_providers.dart';
import '../../core/ai/ai_provider_repository.dart';
import '../../core/ai/base_url.dart';
import '../../core/i18n/app_strings.dart';

class AiProviderPage extends ConsumerStatefulWidget {
  const AiProviderPage({super.key});

  @override
  ConsumerState<AiProviderPage> createState() => _AiProviderPageState();
}

class _AiProviderPageState extends ConsumerState<AiProviderPage> {
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();

  final List<String> _models = <String>[];
  final Map<String, ModelProbeResult> _probeResults =
      <String, ModelProbeResult>{};

  bool _loaded = false;
  bool _saving = false;
  bool _obscureApiKey = true;
  bool _testing = false;
  bool _batchTesting = false;
  bool _batchCancelRequested = false;

  String _selectedModel = '';
  String _status = '';

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(aiProviderRepositoryProvider);
    final client = ref.watch(aiProviderClientProvider);

    if (!_loaded) {
      _loaded = true;
      unawaited(_loadInitial(repo));
    }

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.aiProviderTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _baseUrlController,
            decoration: const InputDecoration(
              labelText: AppStrings.baseUrlLabel,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKeyController,
            obscureText: _obscureApiKey,
            decoration: InputDecoration(
              labelText: AppStrings.apiKeyLabel,
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() {
                    _obscureApiKey = !_obscureApiKey;
                  });
                },
                icon: Icon(
                  _obscureApiKey ? Icons.visibility : Icons.visibility_off,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _models.contains(_selectedModel)
                ? _selectedModel
                : null,
            decoration: const InputDecoration(
              labelText: AppStrings.selectedModelLabel,
            ),
            items: _models
                .map(
                  (String model) => DropdownMenuItem<String>(
                    value: model,
                    child: Text(model, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (String? value) {
              setState(() {
                _selectedModel = value ?? '';
              });
            },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _saving ? null : () => _save(repo),
                child: Text(
                  _saving ? '${AppStrings.save}...' : AppStrings.save,
                ),
              ),
              OutlinedButton(
                onPressed: () => _refreshModels(repo, client),
                child: const Text(AppStrings.refreshModels),
              ),
              OutlinedButton(
                onPressed: _testing
                    ? null
                    : () => _testConnection(repo, client),
                child: Text(
                  _testing
                      ? '${AppStrings.testConnection}...'
                      : AppStrings.testConnection,
                ),
              ),
              OutlinedButton(
                onPressed: _batchTesting
                    ? _requestCancelBatch
                    : () => _batchTestModels(repo, client),
                child: Text(
                  _batchTesting
                      ? AppStrings.stopBatchTest
                      : AppStrings.batchTestModels,
                ),
              ),
              TextButton(
                onPressed: () => _clearCredential(repo),
                child: const Text(AppStrings.clearCredential),
              ),
            ],
          ),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_status),
          ],
          const SizedBox(height: 16),
          if (_models.isEmpty)
            const Text(AppStrings.modelListEmpty)
          else
            ..._models.map(_buildModelRow),
        ],
      ),
    );
  }

  Widget _buildModelRow(String model) {
    final ModelProbeResult? result = _probeResults[model];
    final String subtitle = result == null
        ? '未测试'
        : result.success
        ? '成功 · ${result.elapsedMs}ms'
        : '失败 · ${result.elapsedMs}ms · ${result.error}';

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(model),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: result == null
          ? null
          : Icon(
              result.success ? Icons.check_circle_outline : Icons.error_outline,
              color: result.success ? Colors.green : Colors.red,
            ),
    );
  }

  Future<void> _loadInitial(AiProviderRepository repo) async {
    final AiProviderConfig config = await repo.load();
    if (!mounted) {
      return;
    }

    setState(() {
      _baseUrlController.text = config.baseUrl;
      _apiKeyController.text = config.apiKey;
      _selectedModel = config.selectedModel;
    });
  }

  Future<void> _save(AiProviderRepository repo) async {
    final String baseUrl = _baseUrlController.text.trim();
    final String apiKey = _apiKeyController.text.trim();
    if (baseUrl.isEmpty || apiKey.isEmpty) {
      _setStatus(AppStrings.providerNeedFields);
      return;
    }

    final AiProviderConfig current = await repo.load();
    final bool needsRiskConfirm =
        apiKey.isNotEmpty && !current.storedRiskConfirmed;
    if (needsRiskConfirm) {
      final bool accepted = await _showRiskConfirmDialog();
      if (!accepted) {
        return;
      }
    }

    setState(() {
      _saving = true;
    });

    final AiProviderConfig config = AiProviderConfig(
      baseUrl: baseUrl,
      apiRoot: normalizeBaseUrl(baseUrl),
      apiKey: apiKey,
      selectedModel: _selectedModel,
      storedRiskConfirmed: current.storedRiskConfirmed || apiKey.isNotEmpty,
    );

    await repo.save(config);
    if (!mounted) {
      return;
    }

    setState(() {
      _saving = false;
    });
    _setStatus(AppStrings.saved);
  }

  Future<void> _refreshModels(
    AiProviderRepository repo,
    AiProviderClient client,
  ) async {
    final AiProviderConfig? config = await _loadConfigured(repo);
    if (config == null) {
      return;
    }

    try {
      final List<String> models = await client.fetchModels(config);
      if (!mounted) {
        return;
      }
      setState(() {
        _models
          ..clear()
          ..addAll(models);
        if (!_models.contains(_selectedModel)) {
          _selectedModel = _models.isEmpty ? '' : _models.first;
        }
      });
      _setStatus('模型刷新完成：${models.length} 个');
    } catch (error) {
      _setStatus('刷新模型失败：$error');
    }
  }

  Future<void> _testConnection(
    AiProviderRepository repo,
    AiProviderClient client,
  ) async {
    final AiProviderConfig? config = await _loadConfigured(repo);
    if (config == null) {
      return;
    }

    final String model = _selectedModel.isNotEmpty
        ? _selectedModel
        : (_models.isNotEmpty ? _models.first : '');
    if (model.isEmpty) {
      _setStatus(AppStrings.modelListEmpty);
      return;
    }

    setState(() {
      _testing = true;
    });

    final ModelProbeResult result = await client.probeModel(config, model);
    if (!mounted) {
      return;
    }

    setState(() {
      _testing = false;
      _probeResults[model] = result;
    });

    _setStatus(result.success ? '连接测试成功：$model' : '连接测试失败：${result.error}');
  }

  Future<void> _batchTestModels(
    AiProviderRepository repo,
    AiProviderClient client,
  ) async {
    final AiProviderConfig? config = await _loadConfigured(repo);
    if (config == null) {
      return;
    }

    if (_models.isEmpty) {
      _setStatus(AppStrings.modelListEmpty);
      return;
    }

    setState(() {
      _batchTesting = true;
      _batchCancelRequested = false;
    });
    _setStatus(AppStrings.batchTesting);

    const int concurrency = 3;
    int cursor = 0;

    Future<void> worker() async {
      while (true) {
        if (_batchCancelRequested) {
          return;
        }

        if (cursor >= _models.length) {
          return;
        }
        final int current = cursor;
        cursor += 1;
        final String model = _models[current];
        final ModelProbeResult result = await client.probeModel(config, model);
        if (!mounted) {
          return;
        }

        setState(() {
          _probeResults[model] = result;
        });
      }
    }

    await Future.wait(
      List<Future<void>>.generate(concurrency, (_) => worker()),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _batchTesting = false;
    });
    _setStatus(
      _batchCancelRequested ? AppStrings.batchStopped : AppStrings.batchDone,
    );
  }

  void _requestCancelBatch() {
    setState(() {
      _batchCancelRequested = true;
    });
  }

  Future<void> _clearCredential(AiProviderRepository repo) async {
    await repo.clear();
    if (!mounted) {
      return;
    }

    setState(() {
      _baseUrlController.clear();
      _apiKeyController.clear();
      _selectedModel = '';
      _models.clear();
      _probeResults.clear();
    });
    _setStatus(AppStrings.cleared);
  }

  Future<AiProviderConfig?> _loadConfigured(AiProviderRepository repo) async {
    final String baseUrl = _baseUrlController.text.trim();
    final String apiKey = _apiKeyController.text.trim();
    if (baseUrl.isEmpty || apiKey.isEmpty) {
      _setStatus(AppStrings.providerNeedFields);
      return null;
    }

    final AiProviderConfig config = AiProviderConfig(
      baseUrl: baseUrl,
      apiRoot: normalizeBaseUrl(baseUrl),
      apiKey: apiKey,
      selectedModel: _selectedModel,
      storedRiskConfirmed: true,
    );

    await repo.save(config);
    return config;
  }

  Future<bool> _showRiskConfirmDialog() async {
    bool accepted = false;
    final bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateDialog) {
            return AlertDialog(
              title: const Text(AppStrings.riskTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(AppStrings.riskContent),
                  Row(
                    children: [
                      Checkbox(
                        value: accepted,
                        onChanged: (bool? value) {
                          setStateDialog(() {
                            accepted = value ?? false;
                          });
                        },
                      ),
                      const Expanded(child: Text(AppStrings.riskCheckbox)),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(AppStrings.cancel),
                ),
                FilledButton(
                  onPressed: accepted
                      ? () => Navigator.of(context).pop(true)
                      : null,
                  child: const Text(AppStrings.confirm),
                ),
              ],
            );
          },
        );
      },
    );

    return confirm ?? false;
  }

  void _setStatus(String text) {
    if (!mounted) {
      return;
    }
    setState(() {
      _status = text;
    });
  }
}
