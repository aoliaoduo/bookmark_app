import 'package:flutter/material.dart';

import 'bookmark_detail_page.dart';
import 'note_detail_page.dart';
import 'todo_detail_page.dart';

abstract final class EntityDetailRoutes {
  static const String todoPrefix = '/todo/';
  static const String notePrefix = '/note/';
  static const String linkPrefix = '/link/';

  static String todo(String id) => '$todoPrefix$id';
  static String note(String id) => '$notePrefix$id';
  static String link(String id) => '$linkPrefix$id';

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    final String? name = settings.name;
    if (name == null || name.isEmpty) {
      return null;
    }

    if (name.startsWith(todoPrefix)) {
      final String id = name.substring(todoPrefix.length).trim();
      if (id.isEmpty) {
        return null;
      }
      return MaterialPageRoute<bool>(
        settings: settings,
        builder: (_) => TodoDetailPage(todoId: id),
      );
    }

    if (name.startsWith(notePrefix)) {
      final String id = name.substring(notePrefix.length).trim();
      if (id.isEmpty) {
        return null;
      }
      return MaterialPageRoute<bool>(
        settings: settings,
        builder: (_) => NoteDetailPage(noteId: id),
      );
    }

    if (name.startsWith(linkPrefix)) {
      final String id = name.substring(linkPrefix.length).trim();
      if (id.isEmpty) {
        return null;
      }
      return MaterialPageRoute<bool>(
        settings: settings,
        builder: (_) => BookmarkDetailPage(bookmarkId: id),
      );
    }

    return null;
  }

  static Future<bool?> openTodo(BuildContext context, String id) {
    return Navigator.of(context).pushNamed(todo(id)).then((Object? value) {
      return value is bool ? value : null;
    });
  }

  static Future<bool?> openNote(BuildContext context, String id) {
    return Navigator.of(context).pushNamed(note(id)).then((Object? value) {
      return value is bool ? value : null;
    });
  }

  static Future<bool?> openLink(BuildContext context, String id) {
    return Navigator.of(context).pushNamed(link(id)).then((Object? value) {
      return value is bool ? value : null;
    });
  }
}
