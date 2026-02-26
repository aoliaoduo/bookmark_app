import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notify/notification_models.dart';
import '../../core/notify/notification_queue_service.dart';
import '../../core/notify/notify_config.dart';
import '../../core/notify/notify_providers.dart';

class NotificationChannelsPage extends ConsumerStatefulWidget {
  const NotificationChannelsPage({super.key});

  @override
  ConsumerState<NotificationChannelsPage> createState() =>
      _NotificationChannelsPageState();
}

class _NotificationChannelsPageState
    extends ConsumerState<NotificationChannelsPage> {
  final TextEditingController _feishuWebhookController =
      TextEditingController();
  final TextEditingController _feishuSecretController = TextEditingController();
  final TextEditingController _smtpHostController = TextEditingController();
  final TextEditingController _smtpPortController = TextEditingController();
  final TextEditingController _smtpUserController = TextEditingController();
  final TextEditingController _smtpPassController = TextEditingController();
  final TextEditingController _smtpFromController = TextEditingController();
  final TextEditingController _smtpToController = TextEditingController();

  bool _feishuEnabled = false;
  bool _smtpEnabled = false;
  bool _smtpTls = true;
  bool _loaded = false;
  bool _working = false;
  bool _obscureSmtpPass = true;

  String _status = '';
  List<NotificationJob> _jobs = const <NotificationJob>[];

  @override
  void dispose() {
    _feishuWebhookController.dispose();
    _feishuSecretController.dispose();
    _smtpHostController.dispose();
    _smtpPortController.dispose();
    _smtpUserController.dispose();
    _smtpPassController.dispose();
    _smtpFromController.dispose();
    _smtpToController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final NotificationQueueService queueService = ref.watch(
      notificationQueueServiceProvider,
    );
    final repository = ref.watch(notifyConfigRepositoryProvider);

    if (!_loaded) {
      _loaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final NotifyConfigs configs = await repository.loadAll();
        final List<NotificationJob> jobs = await queueService.listRecentJobs();
        if (!mounted) {
          return;
        }
        setState(() {
          _feishuEnabled = configs.feishu.enabled;
          _feishuWebhookController.text = configs.feishu.webhookUrl;
          _feishuSecretController.text = configs.feishu.secret;
          _smtpEnabled = configs.smtp.enabled;
          _smtpHostController.text = configs.smtp.host;
          _smtpPortController.text = '${configs.smtp.port}';
          _smtpTls = configs.smtp.useTls;
          _smtpUserController.text = configs.smtp.username;
          _smtpPassController.text = configs.smtp.password;
          _smtpFromController.text = configs.smtp.from;
          _smtpToController.text = configs.smtp.to;
          _jobs = jobs;
        });
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('通知渠道')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('飞书 Webhook', style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _feishuEnabled,
            onChanged: (bool value) {
              setState(() {
                _feishuEnabled = value;
              });
            },
            title: const Text('启用飞书'),
          ),
          TextField(
            controller: _feishuWebhookController,
            decoration: const InputDecoration(labelText: 'Webhook URL'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _feishuSecretController,
            decoration: const InputDecoration(labelText: '签名 Secret（可选）'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _working ? null : _saveConfig,
                child: const Text('保存配置'),
              ),
              OutlinedButton(
                onPressed: _working ? null : () => _testFeishu(queueService),
                child: const Text('测试飞书发送'),
              ),
            ],
          ),
          const Divider(height: 28),
          Text('SMTP 邮件', style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _smtpEnabled,
            onChanged: (bool value) {
              setState(() {
                _smtpEnabled = value;
              });
            },
            title: const Text('启用 SMTP'),
          ),
          TextField(
            controller: _smtpHostController,
            decoration: const InputDecoration(labelText: 'SMTP Host'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _smtpPortController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Port'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _smtpTls,
                  onChanged: (bool value) {
                    setState(() {
                      _smtpTls = value;
                    });
                  },
                  title: const Text('TLS'),
                ),
              ),
            ],
          ),
          TextField(
            controller: _smtpUserController,
            decoration: const InputDecoration(labelText: 'Username（可选）'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _smtpPassController,
            obscureText: _obscureSmtpPass,
            decoration: InputDecoration(
              labelText: 'Password（可选）',
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() {
                    _obscureSmtpPass = !_obscureSmtpPass;
                  });
                },
                icon: Icon(
                  _obscureSmtpPass ? Icons.visibility : Icons.visibility_off,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _smtpFromController,
            decoration: const InputDecoration(labelText: 'From'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _smtpToController,
            decoration: const InputDecoration(labelText: 'To（逗号分隔）'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: _working ? null : _saveConfig,
                child: const Text('保存配置'),
              ),
              OutlinedButton(
                onPressed: _working ? null : () => _testSmtp(queueService),
                child: const Text('测试邮件发送'),
              ),
            ],
          ),
          const Divider(height: 28),
          Text('队列与日志', style: Theme.of(context).textTheme.titleMedium),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _working ? null : () => _refreshLogs(queueService),
                child: const Text('刷新日志'),
              ),
              OutlinedButton(
                onPressed: _working ? null : () => _processNow(queueService),
                child: const Text('立即处理队列'),
              ),
            ],
          ),
          if (_status.isNotEmpty) ...[const SizedBox(height: 8), Text(_status)],
          const SizedBox(height: 8),
          if (_jobs.isEmpty)
            const Text('暂无通知队列记录')
          else
            ..._jobs.map(_buildJobTile),
        ],
      ),
    );
  }

  Widget _buildJobTile(NotificationJob job) {
    final String status = switch (job.status) {
      NotificationJobStatus.queued => 'queued',
      NotificationJobStatus.sent => 'sent',
      NotificationJobStatus.failed => 'failed',
    };
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text('${job.channel} | $status'),
      subtitle: Text(
        'attempts=${job.attempts} next=${_fmt(job.nextRetryAt)}\n${job.lastError ?? ''}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(_fmt(job.updatedAt)),
    );
  }

  Future<void> _saveConfig() async {
    setState(() {
      _working = true;
    });
    try {
      final repository = ref.read(notifyConfigRepositoryProvider);
      final FeishuNotifyConfig feishu = FeishuNotifyConfig(
        enabled: _feishuEnabled,
        webhookUrl: _feishuWebhookController.text.trim(),
        secret: _feishuSecretController.text.trim(),
      );
      final SmtpNotifyConfig smtp = SmtpNotifyConfig(
        enabled: _smtpEnabled,
        host: _smtpHostController.text.trim(),
        port: int.tryParse(_smtpPortController.text.trim()) ?? 465,
        useTls: _smtpTls,
        username: _smtpUserController.text.trim(),
        password: _smtpPassController.text,
        from: _smtpFromController.text.trim(),
        to: _smtpToController.text.trim(),
      );
      await repository.saveFeishu(feishu);
      await repository.saveSmtp(smtp);
      _setStatus('通知渠道配置已保存');
    } catch (error) {
      _setStatus('保存失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  Future<void> _testFeishu(NotificationQueueService queueService) async {
    await _saveConfig();
    setState(() {
      _working = true;
    });
    try {
      await queueService.sendFeishuTest();
      _setStatus('飞书测试发送成功');
    } catch (error) {
      _setStatus('飞书测试发送失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  Future<void> _testSmtp(NotificationQueueService queueService) async {
    await _saveConfig();
    setState(() {
      _working = true;
    });
    try {
      await queueService.sendSmtpTest();
      _setStatus('SMTP 测试发送成功');
    } catch (error) {
      _setStatus('SMTP 测试发送失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  Future<void> _refreshLogs(NotificationQueueService queueService) async {
    final List<NotificationJob> jobs = await queueService.listRecentJobs();
    if (!mounted) {
      return;
    }
    setState(() {
      _jobs = jobs;
      _status = '日志已刷新，共 ${jobs.length} 条';
    });
  }

  Future<void> _processNow(NotificationQueueService queueService) async {
    setState(() {
      _working = true;
    });
    try {
      final runtime = ref.read(todoReminderRuntimeProvider);
      await runtime.runNowForDebug();
      final List<NotificationJob> jobs = await queueService.listRecentJobs();
      if (!mounted) {
        return;
      }
      setState(() {
        _jobs = jobs;
      });
      _setStatus('队列已执行一次');
    } catch (error) {
      _setStatus('执行失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  String _fmt(int value) {
    if (value <= 0) {
      return '-';
    }
    return DateTime.fromMillisecondsSinceEpoch(value).toLocal().toString();
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
