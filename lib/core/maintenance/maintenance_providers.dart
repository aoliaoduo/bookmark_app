import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../clock/app_clock.dart';
import '../db/db_provider.dart';
import '../search/fts_updater.dart';
import 'maintenance_service.dart';

final Provider<MaintenanceService> maintenanceServiceProvider =
    Provider<MaintenanceService>((Ref ref) {
      final database = ref.watch(appDatabaseProvider).requireValue;
      return MaintenanceService(
        database: database,
        clock: SystemClock(),
        ftsUpdater: FtsUpdater(),
      );
    });
