import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/db/db_provider.dart';
import '../../core/i18n/app_strings.dart';

class TagsPage extends ConsumerWidget {
  const TagsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final database = ref.watch(appDatabaseProvider).requireValue;
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.tags)),
      body: FutureBuilder<List<String>>(
        future: _loadTags(database.db),
        builder: (BuildContext context, AsyncSnapshot<List<String>> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('加载标签失败：${snapshot.error}'));
          }
          final List<String> tags = snapshot.data ?? const <String>[];
          if (tags.isEmpty) {
            return const Center(child: Text(AppStrings.emptyTags));
          }
          return ListView.builder(
            itemCount: tags.length,
            itemBuilder: (BuildContext context, int index) {
              final String tag = tags[index];
              return ListTile(
                title: Text(tag),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text(AppStrings.tagsComingSoon)),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<List<String>> _loadTags(Database db) async {
    final List<Map<String, Object?>> rows = await db.rawQuery('''
      SELECT name
      FROM tags
      ORDER BY name COLLATE NOCASE ASC
      LIMIT 200
    ''');
    return rows
        .map((Map<String, Object?> row) => (row['name'] as String?) ?? '')
        .where((String value) => value.isNotEmpty)
        .toList(growable: false);
  }
}
