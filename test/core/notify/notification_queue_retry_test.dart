import 'dart:io';

import 'package:code/core/clock/app_clock.dart';
import 'package:code/core/db/app_database.dart';
import 'package:code/core/notify/feishu_sender.dart';
import 'package:code/core/notify/local_sender.dart';
import 'package:code/core/notify/notification_queue_repository.dart';
import 'package:code/core/notify/notification_queue_service.dart';
import 'package:code/core/notify/notify_config.dart';
import 'package:code/core/notify/notify_config_repository.dart';
import 'package:code/core/notify/smtp_sender.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _MutableClock implements AppClock {
  _MutableClock(this.value);

  int value;

  @override
  int nowMs() => value;
}

class _AlwaysFailFeishuSender extends FeishuSender {
  @override
  Future<void> send({
    required FeishuNotifyConfig config,
    required String title,
    required String message,
  }) async {
    throw Exception('mock feishu fail');
  }
}

class _NoopSmtpSender extends SmtpSender {
  @override
  Future<void> send({
    required SmtpNotifyConfig config,
    required String title,
    required String message,
  }) async {}
}

class _NoopLocalSender extends LocalSender {
  @override
  Future<void> send({required String title, required String message}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('notification queue retries with backoff on send failure', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'notify_retry_test_',
    );
    final String dbPath = p.join(tempDir.path, 'notify.db');
    final AppDatabase db = await AppDatabase.open(databasePath: dbPath);
    final _MutableClock clock = _MutableClock(1_730_000_000_000);

    final NotifyConfigRepository configRepo = NotifyConfigRepository(db);
    await configRepo.saveFeishu(
      const FeishuNotifyConfig(
        enabled: true,
        webhookUrl: 'https://example.com/hook',
        secret: '',
      ),
    );

    final NotificationQueueRepository queueRepo = NotificationQueueRepository(
      db.db,
    );
    final NotificationQueueService queueService = NotificationQueueService(
      database: db,
      queueRepository: queueRepo,
      notifyConfigRepository: configRepo,
      clock: clock,
      feishuSender: _AlwaysFailFeishuSender(),
      smtpSender: _NoopSmtpSender(),
      localSender: _NoopLocalSender(),
    );

    final bool inserted = await queueRepo.enqueue(
      channel: 'feishu',
      payload: const <String, Object?>{'title': 'todo', 'message': 'reminder'},
      nowMs: clock.nowMs(),
      jobKey: 'unit-job-1',
    );
    expect(inserted, isTrue);

    await queueService.processQueue(limit: 10);
    final first = await queueRepo.listRecent(limit: 1);
    expect(first, hasLength(1));
    expect(first.first.attempts, 1);
    final int firstRetryAt = first.first.nextRetryAt;
    expect(firstRetryAt, greaterThan(clock.nowMs()));

    clock.value = firstRetryAt + 1;
    await queueService.processQueue(limit: 10);
    final second = await queueRepo.listRecent(limit: 1);
    expect(second, hasLength(1));
    expect(second.first.attempts, 2);
    final int secondRetryAt = second.first.nextRetryAt;
    expect(secondRetryAt, greaterThan(firstRetryAt));

    await db.close();
    await tempDir.delete(recursive: true);
  });
}
