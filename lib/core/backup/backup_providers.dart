import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../clock/app_clock.dart';
import '../db/db_provider.dart';
import '../identity/device_identity_service.dart';
import '../sync/webdav/webdav_config_repository.dart';
import 'backup_reminder_service.dart';
import 'backup_settings_repository.dart';
import 'cloud_backup_service.dart';

final Provider<BackupSettingsRepository> backupSettingsRepositoryProvider =
    Provider<BackupSettingsRepository>((Ref ref) {
      final db = ref.watch(appDatabaseProvider).requireValue;
      return BackupSettingsRepository(db);
    });

final Provider<CloudBackupService> cloudBackupServiceProvider =
    Provider<CloudBackupService>((Ref ref) {
      final db = ref.watch(appDatabaseProvider).requireValue;
      return CloudBackupService(
        database: db,
        clock: SystemClock(),
        identityService: DeviceIdentityService(),
      );
    });

final Provider<BackupReminderService> backupReminderServiceProvider =
    Provider<BackupReminderService>((Ref ref) {
      final db = ref.watch(appDatabaseProvider).requireValue;
      return BackupReminderService(
        settingsRepository: ref.watch(backupSettingsRepositoryProvider),
        webDavConfigRepository: WebDavConfigRepository(db),
        cloudBackupService: ref.watch(cloudBackupServiceProvider),
      );
    });
