import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/db_provider.dart';
import 'ai_provider_client.dart';
import 'ai_provider_repository.dart';

final Provider<AiProviderRepository> aiProviderRepositoryProvider =
    Provider<AiProviderRepository>((Ref ref) {
      final database = ref.watch(appDatabaseProvider).requireValue;
      return AiProviderRepository(database);
    });

final Provider<AiProviderClient> aiProviderClientProvider =
    Provider<AiProviderClient>((Ref ref) => const AiProviderClient());
