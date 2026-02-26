import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import '../sync/webdav/webdav_config_repository.dart';
import 'backup_settings_repository.dart';
import 'cloud_backup_service.dart';

class BackupReminderService {
  BackupReminderService({
    required this.settingsRepository,
    required this.webDavConfigRepository,
    required this.cloudBackupService,
  });

  static final Logger _log = Logger('BackupReminderService');

  final BackupSettingsRepository settingsRepository;
  final WebDavConfigRepository webDavConfigRepository;
  final CloudBackupService cloudBackupService;

  Future<void> checkAndPrompt(BuildContext context) async {
    final DateTime now = DateTime.now();
    final bool shouldPrompt = await settingsRepository.shouldPromptNow(now);
    if (!shouldPrompt || !context.mounted) {
      return;
    }

    await settingsRepository.markPromptedToday(now);
    if (!context.mounted) {
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('云备份提醒'),
          content: const Text('现在开始执行云备份吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('稍后'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('开始备份'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    try {
      final config = await webDavConfigRepository.load();
      final settings = await settingsRepository.loadSettings();
      if (!config.isReady) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('WebDAV 未配置，无法执行云备份')));
        }
        return;
      }
      await cloudBackupService.createAndUploadBackup(
        config: config,
        retentionCount: settings.retentionCount,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('云备份完成')));
      }
    } catch (error) {
      _log.warning('提醒备份失败: $error');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('云备份失败：$error')));
      }
    }
  }
}
