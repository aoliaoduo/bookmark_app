import '../db/app_database.dart';
import 'models/search_result_item.dart';

class LocalSearchService {
  LocalSearchService(this.database);

  final AppDatabase database;

  Future<List<SearchResultItem>> search({
    required String query,
    int limit = 50,
    List<String>? types,
  }) async {
    final String keyword = query.trim();
    if (keyword.isEmpty) {
      return const <SearchResultItem>[];
    }

    try {
      return await _searchByMatch(keyword, limit: limit, types: types);
    } catch (_) {
      return _searchByLike(keyword, limit: limit, types: types);
    }
  }

  Future<List<SearchResultItem>> _searchByMatch(
    String keyword, {
    required int limit,
    List<String>? types,
  }) async {
    final StringBuffer where = StringBuffer('search_fts MATCH ?');
    final List<Object?> args = <Object?>[keyword];

    if (types != null && types.isNotEmpty) {
      final String placeholders = List<String>.filled(
        types.length,
        '?',
      ).join(',');
      where.write(' AND entity_type IN ($placeholders)');
      args.addAll(types);
    }

    args.add(limit);

    final rows = await database.db.rawQuery('''
      SELECT entity_type, entity_id, title,
             snippet(search_fts, 3, '[', ']', '...', 10) AS snippet
      FROM search_fts
      WHERE ${where.toString()}
      LIMIT ?
      ''', args);

    return rows
        .map(
          (row) => SearchResultItem(
            entityType: row['entity_type']! as String,
            entityId: row['entity_id']! as String,
            title: (row['title'] as String?) ?? '',
            snippet: (row['snippet'] as String?) ?? '',
          ),
        )
        .toList(growable: false);
  }

  Future<List<SearchResultItem>> _searchByLike(
    String keyword, {
    required int limit,
    List<String>? types,
  }) async {
    final String like = '%$keyword%';
    final StringBuffer where = StringBuffer(
      '(title LIKE ? OR body LIKE ? OR tags LIKE ?)',
    );
    final List<Object?> args = <Object?>[like, like, like];

    if (types != null && types.isNotEmpty) {
      final String placeholders = List<String>.filled(
        types.length,
        '?',
      ).join(',');
      where.write(' AND entity_type IN ($placeholders)');
      args.addAll(types);
    }

    args.add(limit);

    final rows = await database.db.rawQuery('''
      SELECT entity_type, entity_id, title, body AS snippet
      FROM search_fts
      WHERE ${where.toString()}
      LIMIT ?
      ''', args);

    return rows
        .map(
          (row) => SearchResultItem(
            entityType: row['entity_type']! as String,
            entityId: row['entity_id']! as String,
            title: (row['title'] as String?) ?? '',
            snippet: (row['snippet'] as String?) ?? '',
          ),
        )
        .toList(growable: false);
  }
}
