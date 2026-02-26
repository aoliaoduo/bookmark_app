import 'dart:async';

import 'package:logging/logging.dart';

import '../clock/app_clock.dart';
import 'notification_queue_service.dart';

class TodoReminderRuntime {
  TodoReminderRuntime({required this.queueService, required this.clock});

  static final Logger _log = Logger('TodoReminderRuntime');

  final NotificationQueueService queueService;
  final AppClock clock;

  Timer? _timer;
  bool _tickRunning = false;
  bool _started = false;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    await _tick();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(_tick());
    });
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  Future<void> runNowForDebug() => _tick();

  Future<void> _tick() async {
    if (_tickRunning) {
      return;
    }
    _tickRunning = true;
    try {
      final int nowMs = clock.nowMs();
      await queueService.enqueueDueTodoJobs(nowMs: nowMs);
      await queueService.processQueue(limit: 20);
    } catch (error, stack) {
      _log.warning('提醒轮询失败: $error\n$stack');
    } finally {
      _tickRunning = false;
    }
  }
}
