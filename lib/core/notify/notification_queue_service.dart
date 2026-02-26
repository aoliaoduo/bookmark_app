import 'dart:collection';

import 'package:logging/logging.dart';

import '../clock/app_clock.dart';
import '../db/app_database.dart';
import 'feishu_sender.dart';
import 'local_sender.dart';
import 'notification_models.dart';
import 'notification_queue_repository.dart';
import 'notify_config.dart';
import 'notify_config_repository.dart';
import 'smtp_sender.dart';

class NotificationQueueService {
  NotificationQueueService({
    required this.database,
    required this.queueRepository,
    required this.notifyConfigRepository,
    required this.clock,
    FeishuSender? feishuSender,
    SmtpSender? smtpSender,
    LocalSender? localSender,
  }) : _feishuSender = feishuSender ?? FeishuSender(),
       _smtpSender = smtpSender ?? SmtpSender(),
       _localSender = localSender ?? LocalSender();

  static final Logger _log = Logger('NotificationQueueService');
  static const List<int> _retryBackoffSeconds = <int>[
    60,
    120,
    240,
    480,
    900,
    1800,
    3600,
  ];
  static const int _maxAttempts = 7;

  final AppDatabase database;
  final NotificationQueueRepository queueRepository;
  final NotifyConfigRepository notifyConfigRepository;
  final AppClock clock;
  final FeishuSender _feishuSender;
  final SmtpSender _smtpSender;
  final LocalSender _localSender;

  final Queue<int> _feishuSecondWindow = Queue<int>();
  final Queue<int> _feishuMinuteWindow = Queue<int>();

  bool _processing = false;

  Future<void> enqueueDueTodoJobs({required int nowMs, int limit = 50}) async {
    final NotifyConfigs configs = await notifyConfigRepository.loadAll();
    final List<Map<String, Object?>> rows = await database.db.rawQuery(
      '''
      SELECT id, title, remind_at
      FROM todos
      WHERE deleted = 0
        AND status = ?
        AND remind_at IS NOT NULL
        AND remind_at <= ?
      ORDER BY remind_at ASC
      LIMIT ?
      ''',
      <Object?>[TodoStatusCode.open, nowMs, limit],
    );

    for (final Map<String, Object?> row in rows) {
      final String todoId = row['id']! as String;
      final String title = (row['title'] as String?)?.trim().isNotEmpty == true
          ? row['title']! as String
          : '未命名待办';
      final int remindAt = (row['remind_at'] as num?)?.toInt() ?? nowMs;
      final String msg = '待办提醒：$title';
      final Map<String, Object?> payload = <String, Object?>{
        'todo_id': todoId,
        'title': '待办到点提醒',
        'message': msg,
        'remind_at': remindAt,
      };

      await queueRepository.enqueue(
        channel: 'local',
        jobKey: 'todo-local-$todoId-$remindAt',
        payload: payload,
        nowMs: nowMs,
      );
      if (configs.feishu.isReady) {
        await queueRepository.enqueue(
          channel: 'feishu',
          jobKey: 'todo-feishu-$todoId-$remindAt',
          payload: payload,
          nowMs: nowMs,
        );
      }
      if (configs.smtp.isReady) {
        await queueRepository.enqueue(
          channel: 'smtp',
          jobKey: 'todo-smtp-$todoId-$remindAt',
          payload: payload,
          nowMs: nowMs,
        );
      }
    }
  }

  Future<void> processQueue({int limit = 20}) async {
    if (_processing) {
      return;
    }
    _processing = true;
    try {
      final int nowMs = clock.nowMs();
      final NotifyConfigs configs = await notifyConfigRepository.loadAll();
      final List<NotificationJob> jobs = await queueRepository.listDueJobs(
        nowMs: nowMs,
        limit: limit,
      );
      for (final NotificationJob job in jobs) {
        await _processSingle(job, nowMs: clock.nowMs(), configs: configs);
      }
    } finally {
      _processing = false;
    }
  }

  Future<void> sendFeishuTest() async {
    final FeishuNotifyConfig config = await notifyConfigRepository.loadFeishu();
    await _feishuSender.send(
      config: config,
      title: 'AI Reminder Test',
      message: 'Feishu test message from app.',
    );
  }

  Future<void> sendSmtpTest() async {
    final SmtpNotifyConfig config = await notifyConfigRepository.loadSmtp();
    await _smtpSender.send(
      config: config,
      title: 'AI Reminder Test',
      message: 'SMTP test message from app.',
    );
  }

  Future<List<NotificationJob>> listRecentJobs({int limit = 80}) {
    return queueRepository.listRecent(limit: limit);
  }

  Future<void> _processSingle(
    NotificationJob job, {
    required int nowMs,
    required NotifyConfigs configs,
  }) async {
    final String title = (job.payload['title'] as String?) ?? 'AI Reminder';
    final String message = (job.payload['message'] as String?) ?? '';

    try {
      switch (job.channel) {
        case 'local':
          await _localSender.send(title: title, message: message);
          break;
        case 'feishu':
          if (await _beforeSendFeishu(job, nowMs: nowMs)) {
            return;
          }
          await _feishuSender.send(
            config: configs.feishu,
            title: title,
            message: message,
          );
          _recordFeishuSent(nowMs);
          break;
        case 'smtp':
          await _smtpSender.send(
            config: configs.smtp,
            title: title,
            message: message,
          );
          break;
        default:
          throw Exception('未知通知通道: ${job.channel}');
      }
      await queueRepository.markSent(jobId: job.id, nowMs: nowMs);
    } catch (error) {
      final int attempts = job.attempts + 1;
      final bool terminal = attempts >= _maxAttempts;
      final int delaySeconds =
          _retryBackoffSeconds[(attempts - 1).clamp(
            0,
            _retryBackoffSeconds.length - 1,
          )];
      final int nextRetryAt = nowMs + delaySeconds * 1000;
      await queueRepository.markRetry(
        job: job,
        nowMs: nowMs,
        nextRetryAt: nextRetryAt,
        lastError: error.toString(),
        terminal: terminal,
      );
      _log.warning('通知发送失败(${job.channel}) attempt=$attempts: $error');
    }
  }

  Future<bool> _beforeSendFeishu(
    NotificationJob job, {
    required int nowMs,
  }) async {
    final int nextAllowed = _nextAllowedFeishuTime(nowMs);
    if (nextAllowed <= nowMs) {
      return false;
    }
    await queueRepository.postpone(
      jobId: job.id,
      nowMs: nowMs,
      nextRetryAt: nextAllowed,
      reason: '飞书限速退避',
    );
    return true;
  }

  int _nextAllowedFeishuTime(int nowMs) {
    while (_feishuSecondWindow.isNotEmpty &&
        nowMs - _feishuSecondWindow.first >= 1000) {
      _feishuSecondWindow.removeFirst();
    }
    while (_feishuMinuteWindow.isNotEmpty &&
        nowMs - _feishuMinuteWindow.first >= 60000) {
      _feishuMinuteWindow.removeFirst();
    }
    if (_feishuSecondWindow.length >= 5) {
      return _feishuSecondWindow.first + 1000;
    }
    if (_feishuMinuteWindow.length >= 100) {
      return _feishuMinuteWindow.first + 60000;
    }
    return nowMs;
  }

  void _recordFeishuSent(int nowMs) {
    _feishuSecondWindow.addLast(nowMs);
    _feishuMinuteWindow.addLast(nowMs);
  }
}
