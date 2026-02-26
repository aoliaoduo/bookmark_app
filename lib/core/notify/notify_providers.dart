import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../clock/app_clock.dart';
import '../db/db_provider.dart';
import 'notification_queue_repository.dart';
import 'notification_queue_service.dart';
import 'notify_config_repository.dart';
import 'todo_reminder_runtime.dart';

final Provider<NotifyConfigRepository> notifyConfigRepositoryProvider =
    Provider<NotifyConfigRepository>((Ref ref) {
      final database = ref.watch(appDatabaseProvider).requireValue;
      return NotifyConfigRepository(database);
    });

final Provider<NotificationQueueRepository>
notificationQueueRepositoryProvider = Provider<NotificationQueueRepository>((
  Ref ref,
) {
  final database = ref.watch(appDatabaseProvider).requireValue;
  return NotificationQueueRepository(database.db);
});

final Provider<NotificationQueueService> notificationQueueServiceProvider =
    Provider<NotificationQueueService>((Ref ref) {
      final database = ref.watch(appDatabaseProvider).requireValue;
      return NotificationQueueService(
        database: database,
        queueRepository: ref.watch(notificationQueueRepositoryProvider),
        notifyConfigRepository: ref.watch(notifyConfigRepositoryProvider),
        clock: SystemClock(),
      );
    });

final Provider<TodoReminderRuntime> todoReminderRuntimeProvider =
    Provider<TodoReminderRuntime>((Ref ref) {
      final TodoReminderRuntime runtime = TodoReminderRuntime(
        queueService: ref.watch(notificationQueueServiceProvider),
        clock: SystemClock(),
      );
      ref.onDispose(() {
        runtime.dispose();
      });
      return runtime;
    });
