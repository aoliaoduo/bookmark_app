import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock/app_clock.dart';
import '../../../core/clock/lamport_clock.dart';
import '../../../core/db/db_provider.dart';
import '../../../core/identity/device_identity_service.dart';
import '../../../core/search/fts_updater.dart';
import 'library_repository.dart';

final Provider<DeviceIdentityService> deviceIdentityServiceProvider =
    Provider<DeviceIdentityService>((Ref ref) => DeviceIdentityService());

final Provider<LamportClock> lamportClockProvider = Provider<LamportClock>(
  (Ref ref) => LamportClock(),
);

final Provider<AppClock> appClockProvider = Provider<AppClock>(
  (Ref ref) => SystemClock(),
);

final Provider<LibraryRepository> libraryRepositoryProvider =
    Provider<LibraryRepository>((Ref ref) {
      final database = ref.watch(appDatabaseProvider).requireValue;
      return LibraryRepository(
        database: database,
        identityService: ref.watch(deviceIdentityServiceProvider),
        lamportClock: ref.watch(lamportClockProvider),
        clock: ref.watch(appClockProvider),
        ftsUpdater: FtsUpdater(),
      );
    });
