import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider, Ref;
import 'package:flutter_riverpod/legacy.dart' show StateNotifierProvider;

import '../../core/clock/app_clock.dart';
import '../../core/db/db_provider.dart';
import 'data/focus_state_repository.dart';
import 'focus_controller.dart';
import 'notifications/focus_notification_scheduler.dart';

final Provider<AppClock> focusClockProvider = Provider<AppClock>(
  (Ref ref) => SystemClock(),
);

final Provider<FocusStateRepository> focusStateRepositoryProvider =
    Provider<FocusStateRepository>((Ref ref) {
      final database = ref.watch(appDatabaseProvider).requireValue;
      return FocusStateRepository(database);
    });

final Provider<FocusNotificationScheduler> focusNotificationSchedulerProvider =
    Provider<FocusNotificationScheduler>(
      (Ref ref) => const NoopFocusNotificationScheduler(),
    );

final StateNotifierProvider<FocusController, FocusControllerState>
focusControllerProvider =
    StateNotifierProvider<FocusController, FocusControllerState>((ref) {
      return FocusController(
        repository: ref.watch(focusStateRepositoryProvider),
        clock: ref.watch(focusClockProvider),
        notificationScheduler: ref.watch(focusNotificationSchedulerProvider),
      );
    });
