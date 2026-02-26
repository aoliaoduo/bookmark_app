import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/db/db_provider.dart';
import '../../core/i18n/app_strings.dart';
import 'tag_result_page.dart';

class _TagEntry {
  const _TagEntry({
    required this.id,
    required this.name,
    required this.bindCount,
  });

  final String id;
  final String name;
  final int bindCount;
}

class TagsPage extends ConsumerWidget {
  const TagsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final database = ref.watch(appDatabaseProvider).requireValue;
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.tags)),
      body: FutureBuilder<List<_TagEntry>>(
        future: _loadTags(database.db),
        builder: (BuildContext context, AsyncSnapshot<List<_TagEntry>> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                '${AppStrings.tagsLoadFailedPrefix}${snapshot.error}',
              ),
            );
          }
          final List<_TagEntry> tags = snapshot.data ?? const <_TagEntry>[];
          if (tags.isEmpty) {
            return const Center(child: Text(AppStrings.emptyTags));
          }
          return ListView.builder(
            itemCount: tags.length,
            itemBuilder: (BuildContext context, int index) {
              final _TagEntry tag = tags[index];
              return ListTile(
                dense: true,
                title: Text(tag.name),
                subtitle: Text(
                  '${AppStrings.tagsBoundCountPrefix} ${tag.bindCount} ${AppStrings.tagsBoundCountSuffix}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          TagResultPage(tagId: tag.id, tagName: tag.name),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<List<_TagEntry>> _loadTags(Database db) async {
    final List<Map<String, Object?>> rows = await db.rawQuery('''
      SELECT t.id, t.name, COUNT(et.entity_id) AS bind_count
      FROM tags t
      LEFT JOIN entity_tags et ON et.tag_id = t.id
      GROUP BY t.id
      ORDER BY t.name COLLATE NOCASE ASC
      LIMIT 500
    ''');
    return rows
        .map(
          (Map<String, Object?> row) => _TagEntry(
            id: (row['id'] as String?) ?? '',
            name: (row['name'] as String?) ?? '',
            bindCount: (row['bind_count'] as num?)?.toInt() ?? 0,
          ),
        )
        .where(
          ((_TagEntry value) => value.id.isNotEmpty && value.name.isNotEmpty),
        )
        .toList(growable: false);
  }
}
