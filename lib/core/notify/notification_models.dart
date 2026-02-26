import 'dart:convert';

enum NotificationJobStatus { queued, sent, failed }

String notificationJobStatusToDb(NotificationJobStatus status) {
  return switch (status) {
    NotificationJobStatus.queued => 'queued',
    NotificationJobStatus.sent => 'sent',
    NotificationJobStatus.failed => 'failed',
  };
}

NotificationJobStatus notificationJobStatusFromDb(String rawStatus) {
  return switch (rawStatus) {
    'sent' => NotificationJobStatus.sent,
    'failed' => NotificationJobStatus.failed,
    _ => NotificationJobStatus.queued,
  };
}

class NotificationJob {
  const NotificationJob({
    required this.id,
    required this.channel,
    required this.jobKey,
    required this.status,
    required this.payloadJson,
    required this.attempts,
    required this.nextRetryAt,
    required this.createdAt,
    required this.updatedAt,
    this.lastError,
    this.sentAt,
  });

  final String id;
  final String channel;
  final String? jobKey;
  final NotificationJobStatus status;
  final String payloadJson;
  final int attempts;
  final int nextRetryAt;
  final int createdAt;
  final int updatedAt;
  final String? lastError;
  final int? sentAt;

  Map<String, Object?> get payload {
    final Object? decoded = jsonDecode(payloadJson);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
    return <String, Object?>{};
  }

  factory NotificationJob.fromDb(Map<String, Object?> row) {
    final String rawStatus = (row['status'] as String?) ?? 'queued';
    return NotificationJob(
      id: row['id']! as String,
      channel: row['channel']! as String,
      jobKey: row['job_key'] as String?,
      status: notificationJobStatusFromDb(rawStatus),
      payloadJson: row['payload_json'] as String,
      attempts: ((row['attempts'] as num?)?.toInt() ?? 0),
      nextRetryAt: ((row['next_retry_at'] as num?)?.toInt() ?? 0),
      createdAt: ((row['created_at'] as num?)?.toInt() ?? 0),
      updatedAt: ((row['updated_at'] as num?)?.toInt() ?? 0),
      lastError: row['last_error'] as String?,
      sentAt: (row['sent_at'] as num?)?.toInt(),
    );
  }

  NotificationJob copyWith({
    NotificationJobStatus? status,
    int? attempts,
    int? nextRetryAt,
    int? updatedAt,
    String? lastError,
    bool clearLastError = false,
    int? sentAt,
  }) {
    return NotificationJob(
      id: id,
      channel: channel,
      jobKey: jobKey,
      status: status ?? this.status,
      payloadJson: payloadJson,
      attempts: attempts ?? this.attempts,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      sentAt: sentAt ?? this.sentAt,
    );
  }
}
