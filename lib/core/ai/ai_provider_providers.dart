import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../clock/app_clock.dart';
import '../clock/lamport_clock.dart';
import '../identity/device_identity_service.dart';
import '../sync/change_log_repository.dart';
import '../db/db_provider.dart';
import 'ai_provider_client.dart';
import 'ai_provider_repository.dart';

final Provider<AiProviderRepository> aiProviderRepositoryProvider =
    Provider<AiProviderRepository>((Ref ref) {
      final database = ref.watch(appDatabaseProvider).requireValue;
      return AiProviderRepository(
        database: database,
        identityService: DeviceIdentityService(),
        lamportClock: LamportClock(),
        clock: SystemClock(),
        changeLogRepository: ChangeLogRepository(database.db),
      );
    });

final Provider<AiProviderClient> aiProviderClientProvider =
    Provider<AiProviderClient>((Ref ref) => const AiProviderClient());
