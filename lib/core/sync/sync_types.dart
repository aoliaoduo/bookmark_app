import '../domain/bookmark.dart';

enum SyncOpType { upsert, delete }

class SyncOp {
  const SyncOp({
    required this.opId,
    required this.type,
    required this.bookmark,
    required this.occurredAt,
    required this.deviceId,
  });

  final String opId;
  final SyncOpType type;
  final Bookmark bookmark;
  final DateTime occurredAt;
  final String deviceId;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'opId': opId,
      'type': type.name,
      'bookmark': bookmark.toJson(),
      'occurredAt': occurredAt.toUtc().toIso8601String(),
      'deviceId': deviceId,
    };
  }

  static SyncOp fromJson(Map<String, dynamic> json) {
    return SyncOp(
      opId: json['opId'] as String,
      type: SyncOpType.values.firstWhere(
        (SyncOpType t) => t.name == json['type'],
      ),
      bookmark: Bookmark.fromJson(json['bookmark'] as Map<String, dynamic>),
      occurredAt: DateTime.parse(json['occurredAt'] as String).toUtc(),
      deviceId: json['deviceId'] as String,
    );
  }
}

class SyncBatch {
  const SyncBatch({
    required this.deviceId,
    required this.createdAt,
    required this.ops,
  });

  final String deviceId;
  final DateTime createdAt;
  final List<SyncOp> ops;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'deviceId': deviceId,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'ops': ops.map((SyncOp e) => e.toJson()).toList(),
    };
  }

  static SyncBatch fromJson(Map<String, dynamic> json) {
    return SyncBatch(
      deviceId: json['deviceId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      ops: (json['ops'] as List<dynamic>)
          .map((dynamic e) => SyncOp.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
