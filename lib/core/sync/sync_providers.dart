import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateNotifierProvider;

import '../clock/app_clock.dart';
import '../db/db_provider.dart';
import '../identity/device_identity_service.dart';
import 'sync_runtime_service.dart';
import 'webdav/webdav_config_repository.dart';

final Provider<WebDavConfigRepository> webDavConfigRepositoryProvider =
    Provider<WebDavConfigRepository>((Ref ref) {
      final database = ref.watch(appDatabaseProvider).requireValue;
      return WebDavConfigRepository(database);
    });

final StateNotifierProvider<SyncRuntimeService, SyncRuntimeState>
syncRuntimeProvider =
    StateNotifierProvider<SyncRuntimeService, SyncRuntimeState>((ref) {
      final database = ref.watch(appDatabaseProvider).requireValue;
      return SyncRuntimeService(
        database: database,
        configRepository: ref.watch(webDavConfigRepositoryProvider),
        clock: SystemClock(),
        identityService: DeviceIdentityService(),
      );
    });
