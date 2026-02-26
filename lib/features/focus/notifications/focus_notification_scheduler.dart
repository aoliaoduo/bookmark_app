import '../../../core/focus/focus_timer.dart';

abstract interface class FocusNotificationScheduler {
  Future<void> initialize();

  Future<void> scheduleForState(
    FocusTimerSnapshot snapshot, {
    required int nowMs,
  });

  Future<void> cancelAll();

  Future<void> scheduleSelfCheck({int afterSeconds = 10});
}

class NoopFocusNotificationScheduler implements FocusNotificationScheduler {
  const NoopFocusNotificationScheduler();

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> scheduleForState(
    FocusTimerSnapshot snapshot, {
    required int nowMs,
  }) async {}

  @override
  Future<void> scheduleSelfCheck({int afterSeconds = 10}) async {}
}
