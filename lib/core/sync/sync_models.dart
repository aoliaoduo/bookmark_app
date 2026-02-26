import 'dart:convert';

enum SyncOperation { upsert, delete }

class SyncChange {
  const SyncChange({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.lamport,
    required this.deviceId,
    required this.createdAt,
    this.payloadJson,
  });

  final String id;
  final String entityType;
  final String entityId;
  final SyncOperation operation;
  final int lamport;
  final String deviceId;
  final int createdAt;
  final String? payloadJson;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'entity_type': entityType,
      'entity_id': entityId,
      'operation': operation.name,
      'lamport': lamport,
      'device_id': deviceId,
      'created_at': createdAt,
      'payload_json': payloadJson,
    };
  }

  factory SyncChange.fromJson(Map<String, Object?> map) {
    return SyncChange(
      id: map['id']! as String,
      entityType: map['entity_type']! as String,
      entityId: map['entity_id']! as String,
      operation: _decodeOperation(map['operation']),
      lamport: (map['lamport'] as num).toInt(),
      deviceId: map['device_id']! as String,
      createdAt: (map['created_at'] as num).toInt(),
      payloadJson: map['payload_json'] as String?,
    );
  }

  factory SyncChange.fromDb(Map<String, Object?> row) {
    return SyncChange(
      id: row['id']! as String,
      entityType: row['entity_type']! as String,
      entityId: row['entity_id']! as String,
      operation: _decodeOperation(row['operation']),
      lamport: (row['lamport']! as num).toInt(),
      deviceId: row['device_id']! as String,
      createdAt: (row['created_at']! as num).toInt(),
      payloadJson: row['payload_json'] as String?,
    );
  }

  static SyncOperation _decodeOperation(Object? raw) {
    return raw?.toString() == SyncOperation.delete.name
        ? SyncOperation.delete
        : SyncOperation.upsert;
  }
}

class SyncObject {
  const SyncObject({
    required this.entityType,
    required this.entityId,
    required this.lamport,
    required this.deviceId,
    required this.deleted,
    required this.content,
  });

  final String entityType;
  final String entityId;
  final int lamport;
  final String deviceId;
  final bool deleted;
  final Map<String, Object?> content;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'entity_type': entityType,
      'entity_id': entityId,
      'lamport': lamport,
      'device_id': deviceId,
      'deleted': deleted ? 1 : 0,
      'content': content,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  factory SyncObject.fromJson(Map<String, Object?> map) {
    return SyncObject(
      entityType: map['entity_type']! as String,
      entityId: map['entity_id']! as String,
      lamport: (map['lamport']! as num).toInt(),
      deviceId: map['device_id']! as String,
      deleted: ((map['deleted'] as num?)?.toInt() ?? 0) != 0,
      content: (map['content'] as Map<String, Object?>?) ?? <String, Object?>{},
    );
  }

  factory SyncObject.fromJsonString(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('SyncObject json invalid');
    }
    return SyncObject.fromJson(decoded);
  }
}

class SyncState {
  const SyncState({
    required this.lastSyncStartedAt,
    required this.lastSyncFinishedAt,
    required this.nextAllowedSyncAt,
    required this.backoffUntil,
    required this.lastError,
    required this.lastAppliedChangeId,
    required this.lastPushedChangeId,
    required this.requestWindowStartedAt,
    required this.requestCountInWindow,
    required this.updatedAt,
  });

  static const String singletonId = 'singleton';

  final int? lastSyncStartedAt;
  final int? lastSyncFinishedAt;
  final int? nextAllowedSyncAt;
  final int? backoffUntil;
  final String? lastError;
  final String? lastAppliedChangeId;
  final String? lastPushedChangeId;
  final int? requestWindowStartedAt;
  final int requestCountInWindow;
  final int updatedAt;

  factory SyncState.empty({required int nowMs}) {
    return SyncState(
      lastSyncStartedAt: null,
      lastSyncFinishedAt: null,
      nextAllowedSyncAt: null,
      backoffUntil: null,
      lastError: null,
      lastAppliedChangeId: null,
      lastPushedChangeId: null,
      requestWindowStartedAt: null,
      requestCountInWindow: 0,
      updatedAt: nowMs,
    );
  }

  SyncState copyWith({
    int? lastSyncStartedAt,
    int? lastSyncFinishedAt,
    int? nextAllowedSyncAt,
    int? backoffUntil,
    String? lastError,
    bool clearError = false,
    String? lastAppliedChangeId,
    String? lastPushedChangeId,
    int? requestWindowStartedAt,
    int? requestCountInWindow,
    int? updatedAt,
  }) {
    return SyncState(
      lastSyncStartedAt: lastSyncStartedAt ?? this.lastSyncStartedAt,
      lastSyncFinishedAt: lastSyncFinishedAt ?? this.lastSyncFinishedAt,
      nextAllowedSyncAt: nextAllowedSyncAt ?? this.nextAllowedSyncAt,
      backoffUntil: backoffUntil ?? this.backoffUntil,
      lastError: clearError ? null : (lastError ?? this.lastError),
      lastAppliedChangeId: lastAppliedChangeId ?? this.lastAppliedChangeId,
      lastPushedChangeId: lastPushedChangeId ?? this.lastPushedChangeId,
      requestWindowStartedAt:
          requestWindowStartedAt ?? this.requestWindowStartedAt,
      requestCountInWindow: requestCountInWindow ?? this.requestCountInWindow,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory SyncState.fromDb(Map<String, Object?> row) {
    int? readNullableInt(Object? raw) {
      if (raw == null) {
        return null;
      }
      return (raw as num).toInt();
    }

    return SyncState(
      lastSyncStartedAt: readNullableInt(row['last_sync_started_at']),
      lastSyncFinishedAt: readNullableInt(row['last_sync_finished_at']),
      nextAllowedSyncAt: readNullableInt(row['next_allowed_sync_at']),
      backoffUntil: readNullableInt(row['backoff_until']),
      lastError: row['last_error'] as String?,
      lastAppliedChangeId: row['last_applied_change_id'] as String?,
      lastPushedChangeId: row['last_pushed_change_id'] as String?,
      requestWindowStartedAt: readNullableInt(row['request_window_started_at']),
      requestCountInWindow:
          ((row['request_count_in_window'] as num?)?.toInt() ?? 0),
      updatedAt: (row['updated_at'] as num).toInt(),
    );
  }
}

class SyncRunResult {
  const SyncRunResult({
    required this.pulledCount,
    required this.appliedCount,
    required this.pushedCount,
    required this.skippedByThrottle,
    required this.skippedByBackoff,
    this.message,
  });

  final int pulledCount;
  final int appliedCount;
  final int pushedCount;
  final bool skippedByThrottle;
  final bool skippedByBackoff;
  final String? message;
}

class SyncLogEntry {
  const SyncLogEntry({
    required this.timestampMs,
    required this.level,
    required this.message,
  });

  final int timestampMs;
  final String level;
  final String message;
}
