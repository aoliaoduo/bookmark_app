import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/actions/action_executor.dart';
import '../../core/ai/ai_provider_providers.dart';
import '../../core/ai/router_schema_validator.dart';
import '../../core/ai/router_service.dart';
import '../../core/clock/app_clock.dart';
import '../../core/clock/lamport_clock.dart';
import '../../core/db/db_provider.dart';
import '../../core/identity/device_identity_service.dart';
import 'data/inbox_draft_repository.dart';

final Provider<InboxDraftRepository> inboxDraftRepositoryProvider =
    Provider<InboxDraftRepository>((Ref ref) {
      final database = ref.watch(appDatabaseProvider).requireValue;
      return InboxDraftRepository(database);
    });

final Provider<RouterSchemaValidator> routerSchemaValidatorProvider =
    Provider<RouterSchemaValidator>((Ref ref) => RouterSchemaValidator());

final Provider<RouterService> routerServiceProvider = Provider<RouterService>((
  Ref ref,
) {
  return RouterService(
    client: ref.watch(aiProviderClientProvider),
    validator: ref.watch(routerSchemaValidatorProvider),
  );
});

final Provider<ActionExecutor> actionExecutorProvider =
    Provider<ActionExecutor>((Ref ref) {
      final database = ref.watch(appDatabaseProvider).requireValue;
      return ActionExecutor(
        database: database,
        identityService: DeviceIdentityService(),
        lamportClock: LamportClock(),
        clock: SystemClock(),
      );
    });
