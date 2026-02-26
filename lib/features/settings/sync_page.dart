import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backup/backup_manifest.dart';
import '../../core/backup/backup_providers.dart';
import '../../core/backup/backup_settings_repository.dart';
import '../../core/backup/cloud_backup_service.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/sync/sync_providers.dart';
import '../../core/sync/sync_runtime_service.dart';
import '../../core/sync/webdav/webdav_config.dart';
import 'notification_channels_page.dart';

class SyncPage extends ConsumerStatefulWidget {
  const SyncPage({super.key});

  @override
  ConsumerState<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends ConsumerState<SyncPage> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _backupReminderController =
      TextEditingController();
  final TextEditingController _backupRetentionController =
      TextEditingController();

  bool _loaded = false;
  bool _obscurePassword = true;
  bool _paidPlan = false;
  bool _backupWorking = false;
  String _backupStatus = '';
  List<CloudBackupItem> _backups = const <CloudBackupItem>[];

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _backupReminderController.dispose();
    _backupRetentionController.dispose();
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
        await _loadBackupData(latest.config);
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.syncPageTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const NotificationChannelsPage(),
                  ),
                );
              },
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('通知渠道设置'),
            ),
          ),
          const SizedBox(height: 8),
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
          const Divider(height: 28),
          Text(
            AppStrings.backupSectionTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _backupReminderController,
                  decoration: const InputDecoration(
                    labelText: AppStrings.backupReminderHm,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _backupRetentionController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: AppStrings.backupRetention,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: _saveBackupSettings,
                child: const Text(AppStrings.backupSaveSettings),
              ),
              OutlinedButton(
                onPressed: _backupWorking ? null : _runCloudBackupNow,
                child: Text(
                  _backupWorking
                      ? '${AppStrings.backupRunNow}...'
                      : AppStrings.backupRunNow,
                ),
              ),
              OutlinedButton(
                onPressed: _backupWorking ? null : _refreshBackupList,
                child: const Text(AppStrings.backupRefreshList),
              ),
            ],
          ),
          if (_backupStatus.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(_backupStatus),
          ],
          const SizedBox(height: 8),
          if (_backups.isEmpty)
            const Text('暂无云端备份')
          else
            ..._backups.map((CloudBackupItem item) {
              final String subtitle =
                  'size=${item.sizeBytes ?? 0} | ${item.lastModified?.toLocal() ?? '-'}';
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(item.fileName),
                subtitle: Text(subtitle),
                trailing: TextButton(
                  onPressed: _backupWorking ? null : () => _restoreBackup(item),
                  child: const Text(AppStrings.backupRestore),
                ),
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

  Future<void> _loadBackupData(WebDavConfig config) async {
    final BackupSettingsRepository settingsRepo = ref.read(
      backupSettingsRepositoryProvider,
    );
    final CloudBackupService backupService = ref.read(
      cloudBackupServiceProvider,
    );
    final BackupSettings settings = await settingsRepo.loadSettings();
    final List<CloudBackupItem> backups = await backupService.listCloudBackups(
      config,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _backupReminderController.text = settings.reminderHm;
      _backupRetentionController.text = '${settings.retentionCount}';
      _backups = backups;
    });
  }

  Future<void> _saveBackupSettings() async {
    final BackupSettingsRepository settingsRepo = ref.read(
      backupSettingsRepositoryProvider,
    );
    final String hm = _backupReminderController.text.trim();
    final List<String> parts = hm.split(':');
    final int hour = int.tryParse(parts.isNotEmpty ? parts.first : '') ?? 14;
    final int minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    final int retention =
        int.tryParse(_backupRetentionController.text.trim()) ?? 30;
    await settingsRepo.saveSettings(
      BackupSettings(
        reminderHour: hour.clamp(0, 23),
        reminderMinute: minute.clamp(0, 59),
        retentionCount: retention.clamp(1, 365),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _backupStatus = '备份设置已保存';
    });
  }

  Future<void> _runCloudBackupNow() async {
    final CloudBackupService backupService = ref.read(
      cloudBackupServiceProvider,
    );
    final BackupSettingsRepository settingsRepo = ref.read(
      backupSettingsRepositoryProvider,
    );
    final SyncRuntimeService notifier = ref.read(syncRuntimeProvider.notifier);
    final WebDavConfig config = _collectConfig();
    await notifier.saveConfig(config);
    final BackupSettings settings = await settingsRepo.loadSettings();

    setState(() {
      _backupWorking = true;
      _backupStatus = '云备份执行中...';
    });
    try {
      final BackupRunResult result = await backupService.createAndUploadBackup(
        config: config,
        retentionCount: settings.retentionCount,
      );
      final List<CloudBackupItem> backups = await backupService
          .listCloudBackups(config);
      if (!mounted) {
        return;
      }
      setState(() {
        _backupWorking = false;
        _backups = backups;
        _backupStatus = '备份完成：${result.remotePath}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _backupWorking = false;
        _backupStatus = '备份失败：$error';
      });
    }
  }

  Future<void> _refreshBackupList() async {
    final CloudBackupService backupService = ref.read(
      cloudBackupServiceProvider,
    );
    final WebDavConfig config = _collectConfig();
    final List<CloudBackupItem> backups = await backupService.listCloudBackups(
      config,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _backups = backups;
      _backupStatus = '云端列表已刷新：${backups.length} 份';
    });
  }

  Future<void> _restoreBackup(CloudBackupItem item) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('确认恢复'),
          content: Text('将从 ${item.fileName} 覆盖本地数据库，是否继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('继续'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    final CloudBackupService backupService = ref.read(
      cloudBackupServiceProvider,
    );
    final WebDavConfig config = _collectConfig();
    setState(() {
      _backupWorking = true;
      _backupStatus = '恢复中...';
    });
    try {
      final RestoreRunResult result = await backupService.restoreFromCloud(
        config: config,
        backup: item,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _backupWorking = false;
        _backupStatus = '恢复完成（临时回滚备份：${result.localTempBackupPath}），建议重启应用';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _backupWorking = false;
        _backupStatus = '恢复失败：$error';
      });
    }
  }

  String _fmtTs(int? value) {
    if (value == null || value <= 0) {
      return '-';
    }
    return DateTime.fromMillisecondsSinceEpoch(value).toLocal().toString();
  }
}
