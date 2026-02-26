import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/sync/sync_providers.dart';
import '../../core/sync/sync_runtime_service.dart';
import '../../core/sync/webdav/webdav_config.dart';

class SyncPage extends ConsumerStatefulWidget {
  const SyncPage({super.key});

  @override
  ConsumerState<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends ConsumerState<SyncPage> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _loaded = false;
  bool _obscurePassword = true;
  bool _paidPlan = false;

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SyncRuntimeState state = ref.watch(syncRuntimeProvider);
    final SyncRuntimeService notifier = ref.read(syncRuntimeProvider.notifier);

    if (!_loaded) {
      _loaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await notifier.load();
        if (!mounted) {
          return;
        }
        final SyncRuntimeState latest = ref.read(syncRuntimeProvider);
        _fillFromConfig(latest.config);
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.syncPageTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: AppStrings.webdavUrlLabel,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: AppStrings.webdavUserLabel,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: AppStrings.webdavPasswordLabel,
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
                icon: Icon(
                  _obscurePassword ? Icons.visibility : Icons.visibility_off,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _paidPlan,
            onChanged: (bool value) {
              setState(() {
                _paidPlan = value;
              });
            },
            title: const Text(AppStrings.webdavPaidPlan),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () async {
                  final WebDavConfig config = _collectConfig();
                  await notifier.saveConfig(config);
                },
                child: const Text(AppStrings.syncSaveConfig),
              ),
              OutlinedButton(
                onPressed: state.testing ? null : notifier.testConnection,
                child: Text(
                  state.testing
                      ? '${AppStrings.syncTestConnection}...'
                      : AppStrings.syncTestConnection,
                ),
              ),
              OutlinedButton(
                onPressed: state.running ? null : notifier.runManualSync,
                child: Text(
                  state.running
                      ? '${AppStrings.syncManualNow}...'
                      : AppStrings.syncManualNow,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            AppStrings.syncThrottleHint,
            style: TextStyle(color: Colors.black54),
          ),
          if (state.status.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(state.status),
          ],
          const SizedBox(height: 16),
          Text(
            AppStrings.syncStatusTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'last_sync_started_at: ${_fmtTs(state.syncState.lastSyncStartedAt)}',
          ),
          Text(
            'last_sync_finished_at: ${_fmtTs(state.syncState.lastSyncFinishedAt)}',
          ),
          Text(
            'next_allowed_sync_at: ${_fmtTs(state.syncState.nextAllowedSyncAt)}',
          ),
          Text('backoff_until: ${_fmtTs(state.syncState.backoffUntil)}'),
          Text('last_error: ${state.syncState.lastError ?? ''}'),
          const SizedBox(height: 16),
          Text(
            AppStrings.syncLogTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          if (state.logs.isEmpty)
            const Text('暂无同步日志')
          else
            ...state.logs.reversed.take(20).map((entry) {
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '[${entry.level}] ${entry.message}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(_fmtTs(entry.timestampMs)),
              );
            }),
        ],
      ),
    );
  }

  void _fillFromConfig(WebDavConfig config) {
    _urlController.text = config.baseUrl;
    _usernameController.text = config.username;
    _passwordController.text = config.appPassword;
    _paidPlan = config.paidPlan;
    setState(() {});
  }

  WebDavConfig _collectConfig() {
    return WebDavConfig(
      baseUrl: _urlController.text.trim(),
      username: _usernameController.text.trim(),
      appPassword: _passwordController.text.trim(),
      paidPlan: _paidPlan,
    );
  }

  String _fmtTs(int? value) {
    if (value == null || value <= 0) {
      return '-';
    }
    return DateTime.fromMillisecondsSinceEpoch(value).toLocal().toString();
  }
}
