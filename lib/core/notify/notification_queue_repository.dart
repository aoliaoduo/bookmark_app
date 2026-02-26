import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'notification_models.dart';

class NotificationQueueRepository {
  NotificationQueueRepository(this.db);

  static const Uuid _uuid = Uuid();

  final DatabaseExecutor db;

  Future<bool> enqueue({
    required String channel,
    required Map<String, Object?> payload,
    required int nowMs,
    String? jobKey,
    int? nextRetryAt,
  }) async {
    final int inserted = await db.insert('notification_jobs', <String, Object?>{
      'id': _uuid.v4(),
      'channel': channel,
      'job_key': jobKey,
      'status': notificationJobStatusToDb(NotificationJobStatus.queued),
      'payload_json': jsonEncode(payload),
      'attempts': 0,
      'next_retry_at': nextRetryAt ?? nowMs,
      'last_error': null,
      'created_at': nowMs,
      'updated_at': nowMs,
      'sent_at': null,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return inserted > 0;
  }

  Future<List<NotificationJob>> listDueJobs({
    required int nowMs,
    int limit = 20,
  }) async {
    final List<Map<String, Object?>> rows = await db.query(
      'notification_jobs',
      where: 'status = ? AND next_retry_at <= ?',
      whereArgs: <Object?>[
        notificationJobStatusToDb(NotificationJobStatus.queued),
        nowMs,
      ],
      orderBy: 'next_retry_at ASC, created_at ASC',
      limit: limit,
    );
    return rows
        .map((Map<String, Object?> row) => NotificationJob.fromDb(row))
        .toList(growable: false);
  }

  Future<void> markSent({required String jobId, required int nowMs}) async {
    await db.update(
      'notification_jobs',
      <String, Object?>{
        'status': notificationJobStatusToDb(NotificationJobStatus.sent),
        'updated_at': nowMs,
        'sent_at': nowMs,
        'last_error': null,
      },
      where: 'id = ?',
      whereArgs: <Object?>[jobId],
    );
  }

  Future<void> markRetry({
    required NotificationJob job,
    required int nowMs,
    required int nextRetryAt,
    required String lastError,
    required bool terminal,
  }) async {
    await db.update(
      'notification_jobs',
      <String, Object?>{
        'status': notificationJobStatusToDb(
          terminal
              ? NotificationJobStatus.failed
              : NotificationJobStatus.queued,
        ),
        'attempts': job.attempts + 1,
        'next_retry_at': nextRetryAt,
        'last_error': lastError,
        'updated_at': nowMs,
      },
      where: 'id = ?',
      whereArgs: <Object?>[job.id],
    );
  }

  Future<void> postpone({
    required String jobId,
    required int nowMs,
    required int nextRetryAt,
    required String reason,
  }) async {
    await db.update(
      'notification_jobs',
      <String, Object?>{
        'status': notificationJobStatusToDb(NotificationJobStatus.queued),
        'next_retry_at': nextRetryAt,
        'last_error': reason,
        'updated_at': nowMs,
      },
      where: 'id = ?',
      whereArgs: <Object?>[jobId],
    );
  }

  Future<List<NotificationJob>> listRecent({int limit = 80}) async {
    final List<Map<String, Object?>> rows = await db.query(
      'notification_jobs',
      orderBy: 'updated_at DESC',
      limit: limit,
    );
    return rows
        .map((Map<String, Object?> row) => NotificationJob.fromDb(row))
        .toList(growable: false);
  }
}
