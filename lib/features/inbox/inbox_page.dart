import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_provider_providers.dart';
import '../../core/ai/ai_provider_repository.dart';
import '../../core/ai/router_decision.dart';
import '../../core/i18n/app_strings.dart';
import '../settings/ai_provider_page.dart';
import 'data/inbox_draft_repository.dart';
import 'inbox_providers.dart';

class InboxPage extends ConsumerStatefulWidget {
  const InboxPage({super.key});

  @override
  ConsumerState<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends ConsumerState<InboxPage> {
  final TextEditingController _controller = TextEditingController();

  bool _sending = false;
  String _status = '';
  List<InboxDraft> _drafts = const <InboxDraft>[];

  @override
  void initState() {
    super.initState();
    _refreshDrafts();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: AppStrings.inboxHint,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.edit_note_outlined),
            ),
            minLines: 2,
            maxLines: 4,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.send),
                label: Text(_sending ? AppStrings.sending : AppStrings.send),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AiProviderPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.tune),
                label: const Text(AppStrings.openAiProviderSettings),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_status.isNotEmpty) Text(_status),
          const SizedBox(height: 10),
          const Text(AppStrings.draftListTitle),
          const SizedBox(height: 6),
          Expanded(
            child: _drafts.isEmpty
                ? const Center(child: Text(AppStrings.inboxDraftHint))
                : ListView.builder(
                    itemCount: _drafts.length,
                    itemBuilder: (BuildContext context, int index) {
                      final InboxDraft draft = _drafts[index];
                      return ListTile(
                        dense: true,
                        title: Text(
                          draft.rawInput,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          'retry=${draft.retryCount} | ${draft.lastError}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Wrap(
                          spacing: 6,
                          children: [
                            TextButton(
                              onPressed: _sending
                                  ? null
                                  : () => _retryDraft(draft),
                              child: const Text(AppStrings.retry),
                            ),
                            TextButton(
                              onPressed: _sending
                                  ? null
                                  : () => _deleteDraft(draft.id),
                              child: const Text(AppStrings.delete),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final String input = _controller.text.trim();
    if (input.isEmpty) {
      _setStatus(AppStrings.inboxNeedInput);
      return;
    }

    setState(() {
      _sending = true;
    });

    try {
      await _routeAndExecute(input);
      if (!mounted) {
        return;
      }
      _controller.clear();
      _setStatus(AppStrings.submitSuccess);
    } catch (error) {
      final InboxDraftRepository drafts = ref.read(
        inboxDraftRepositoryProvider,
      );
      await drafts.createDraft(rawInput: input, lastError: error.toString());
      _setStatus('处理失败，已存草稿：$error');
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
      await _refreshDrafts();
    }
  }

  Future<void> _retryDraft(InboxDraft draft) async {
    setState(() {
      _sending = true;
    });

    final InboxDraftRepository drafts = ref.read(inboxDraftRepositoryProvider);
    try {
      await _routeAndExecute(draft.rawInput);
      await drafts.deleteDraft(draft.id);
      _setStatus('草稿重试成功');
    } catch (error) {
      await drafts.markRetryFailed(
        id: draft.id,
        error: error.toString(),
        currentRetry: draft.retryCount,
      );
      _setStatus('草稿重试失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
      await _refreshDrafts();
    }
  }

  Future<void> _deleteDraft(String id) async {
    await ref.read(inboxDraftRepositoryProvider).deleteDraft(id);
    await _refreshDrafts();
  }

  Future<void> _routeAndExecute(String input) async {
    final AiProviderRepository providerRepo = ref.read(
      aiProviderRepositoryProvider,
    );
    final RouterDecision decision = await _route(providerRepo, input);
    await ref.read(actionExecutorProvider).execute(decision, rawInput: input);
  }

  Future<RouterDecision> _route(
    AiProviderRepository providerRepo,
    String input,
  ) async {
    final config = await providerRepo.load();
    final String model = config.selectedModel.trim();

    if (!config.isReady || model.isEmpty) {
      throw Exception(AppStrings.inboxNeedModel);
    }

    return ref
        .read(routerServiceProvider)
        .route(config: config, model: model, userInput: input);
  }

  Future<void> _refreshDrafts() async {
    final List<InboxDraft> items = await ref
        .read(inboxDraftRepositoryProvider)
        .listDrafts();
    if (!mounted) {
      return;
    }
    setState(() {
      _drafts = items;
    });
  }

  void _setStatus(String value) {
    if (!mounted) {
      return;
    }
    setState(() {
      _status = value;
    });
  }
}
