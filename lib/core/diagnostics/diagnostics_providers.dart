import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_provider_providers.dart';
import '../backup/backup_providers.dart';
import '../clock/app_clock.dart';
import '../db/db_provider.dart';
import 'diagnostics_service.dart';

final Provider<DiagnosticsService> diagnosticsServiceProvider =
    Provider<DiagnosticsService>((Ref ref) {
      final database = ref.watch(appDatabaseProvider).requireValue;
      return DiagnosticsService(
        database: database,
        aiProviderRepository: ref.watch(aiProviderRepositoryProvider),
        backupSettingsRepository: ref.watch(backupSettingsRepositoryProvider),
        clock: SystemClock(),
      );
    });
