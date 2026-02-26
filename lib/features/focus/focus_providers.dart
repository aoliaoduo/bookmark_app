import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart'
    show AsyncData, Provider, Ref;
import 'package:flutter_riverpod/legacy.dart' show StateNotifierProvider;

import '../../core/clock/app_clock.dart';
import '../../core/db/app_database.dart';
import '../../core/db/db_provider.dart';
import 'data/focus_state_repository.dart';
import 'focus_controller.dart';
import 'notifications/focus_notification_scheduler.dart';

final Provider<AppClock> focusClockProvider = Provider<AppClock>(
  (Ref ref) => SystemClock(),
);

final Provider<FocusStateRepository> focusStateRepositoryProvider =
    Provider<FocusStateRepository>((Ref ref) {
      final dbAsync = ref.watch(appDatabaseProvider);
      if (dbAsync case AsyncData<AppDatabase>(:final value)) {
        return FocusStateRepository(value);
      }
      return FocusStateRepository.inMemory();
    });

final Provider<FocusNotificationScheduler> focusNotificationSchedulerProvider =
    Provider<FocusNotificationScheduler>((Ref ref) {
      final scheduler = TimerBasedFocusNotificationScheduler(
        clock: ref.watch(focusClockProvider),
        gateway: ShellFocusNotificationGateway(),
      );
      if (Platform.isAndroid) {
        return AndroidAlarmManagerFocusNotificationScheduler(
          fallback: scheduler,
        );
      }
      return scheduler;
    });

final StateNotifierProvider<FocusController, FocusControllerState>
focusControllerProvider =
    StateNotifierProvider<FocusController, FocusControllerState>((ref) {
      return FocusController(
        repository: ref.watch(focusStateRepositoryProvider),
        clock: ref.watch(focusClockProvider),
        notificationScheduler: ref.watch(focusNotificationSchedulerProvider),
      );
    });
