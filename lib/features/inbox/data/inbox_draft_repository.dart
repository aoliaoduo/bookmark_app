import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';

class InboxDraft {
  const InboxDraft({
    required this.id,
    required this.rawInput,
    required this.createdAt,
    required this.lastError,
    required this.retryCount,
  });

  final String id;
  final String rawInput;
  final int createdAt;
  final String lastError;
  final int retryCount;
}

class InboxDraftRepository {
  InboxDraftRepository(this.database);

  static const Uuid _uuid = Uuid();

  final AppDatabase database;

  Future<void> createDraft({
    required String rawInput,
    required String lastError,
  }) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    return database.db.insert('inbox_drafts', {
      'id': _uuid.v4(),
      'raw_input': rawInput,
      'created_at': now,
      'last_error': lastError,
      'retry_count': 0,
    });
  }

  Future<void> markRetryFailed({
    required String id,
    required String error,
    required int currentRetry,
  }) {
    return database.db.update(
      'inbox_drafts',
      {'last_error': error, 'retry_count': currentRetry + 1},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<List<InboxDraft>> listDrafts({int limit = 30}) async {
    final List<Map<String, Object?>> rows = await database.db.query(
      'inbox_drafts',
      orderBy: 'created_at DESC',
      limit: limit,
    );

    return rows
        .map(
          (Map<String, Object?> row) => InboxDraft(
            id: row['id']! as String,
            rawInput: row['raw_input']! as String,
            createdAt: row['created_at']! as int,
            lastError: (row['last_error'] as String?) ?? '',
            retryCount: (row['retry_count'] as int?) ?? 0,
          ),
        )
        .toList(growable: false);
  }

  Future<void> deleteDraft(String id) {
    return database.db.delete(
      'inbox_drafts',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }
}
