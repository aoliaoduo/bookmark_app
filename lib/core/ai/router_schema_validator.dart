class RouterValidationResult {
  const RouterValidationResult({required this.isValid, required this.error});

  final bool isValid;
  final String error;

  static const RouterValidationResult ok = RouterValidationResult(
    isValid: true,
    error: '',
  );
}

class RouterSchemaValidator {
  static const Set<String> _actions = <String>{
    'create_todo',
    'create_note',
    'create_bookmark',
    'search',
    'refresh_bookmark_title',
    'start_focus_timer',
    'maintenance',
  };

  RouterValidationResult validate(Object? input) {
    if (input is! Map<String, Object?>) {
      return _fail('根节点必须是 JSON 对象');
    }

    final Set<String> keys = input.keys.toSet();
    const Set<String> required = <String>{'action', 'confidence', 'payload'};
    if (!keys.containsAll(required)) {
      return _fail('缺少必要字段 action/confidence/payload');
    }
    if (keys.length != 3) {
      return _fail('仅允许字段 action/confidence/payload');
    }

    final String? action = input['action'] as String?;
    final num? confidence = input['confidence'] as num?;
    final Object? payload = input['payload'];

    if (action == null || !_actions.contains(action)) {
      return _fail('action 不合法');
    }
    if (confidence == null || confidence < 0 || confidence > 1) {
      return _fail('confidence 不合法');
    }
    if (payload is! Map<String, Object?>) {
      return _fail('payload 必须是对象');
    }

    return switch (action) {
      'create_todo' => _validateCreateTodo(payload),
      'create_note' => _validateCreateNote(payload),
      'create_bookmark' => _validateCreateBookmark(payload),
      'search' => _validateSearch(payload),
      'refresh_bookmark_title' => _validateRefreshBookmarkTitle(payload),
      'start_focus_timer' => _validateStartFocusTimer(payload),
      'maintenance' => _validateMaintenance(payload),
      _ => _fail('action 不支持'),
    };
  }

  RouterValidationResult _validateCreateTodo(Map<String, Object?> payload) {
    const Set<String> allowed = <String>{
      'title',
      'priority',
      'tags',
      'remind_at',
    };
    if (!_onlyAllowed(payload, allowed)) {
      return _fail('create_todo payload 含非法字段');
    }

    final String? title = payload['title'] as String?;
    final String? priority = payload['priority'] as String?;
    final Object? tags = payload['tags'];
    if (!_stringLen(title, 1, 200)) {
      return _fail('create_todo.title 不合法');
    }
    if (!const <String>{'high', 'medium', 'low'}.contains(priority)) {
      return _fail('create_todo.priority 不合法');
    }
    if (!_tags(tags, 20)) {
      return _fail('create_todo.tags 不合法');
    }

    final Object? remindAt = payload['remind_at'];
    if (remindAt != null && !_remindAt(remindAt)) {
      return _fail('create_todo.remind_at 不合法');
    }

    return RouterValidationResult.ok;
  }

  RouterValidationResult _validateCreateNote(Map<String, Object?> payload) {
    const Set<String> allowed = <String>{'title', 'tags', 'organized_md'};
    if (!_onlyAllowed(payload, allowed)) {
      return _fail('create_note payload 含非法字段');
    }

    final String? title = payload['title'] as String?;
    final Object? tags = payload['tags'];
    final String? organizedMd = payload['organized_md'] as String?;

    if (!_stringLen(title, 1, 200)) {
      return _fail('create_note.title 不合法');
    }
    if (!_tags(tags, 30)) {
      return _fail('create_note.tags 不合法');
    }
    if (!_stringLen(organizedMd, 1, 1000000)) {
      return _fail('create_note.organized_md 不合法');
    }

    return RouterValidationResult.ok;
  }

  RouterValidationResult _validateCreateBookmark(Map<String, Object?> payload) {
    if (!_onlyAllowed(payload, const <String>{'url'})) {
      return _fail('create_bookmark payload 含非法字段');
    }
    final String? url = payload['url'] as String?;
    if (!_stringLen(url, 5, 2000)) {
      return _fail('create_bookmark.url 不合法');
    }
    return RouterValidationResult.ok;
  }

  RouterValidationResult _validateSearch(Map<String, Object?> payload) {
    const Set<String> allowed = <String>{'query', 'mode', 'filters'};
    if (!_onlyAllowed(payload, allowed)) {
      return _fail('search payload 含非法字段');
    }

    final String? query = payload['query'] as String?;
    if (!_stringLen(query, 1, 500)) {
      return _fail('search.query 不合法');
    }

    final String? mode = payload['mode'] as String?;
    if (mode != null && !const <String>{'normal', 'deep'}.contains(mode)) {
      return _fail('search.mode 不合法');
    }

    final Object? filters = payload['filters'];
    if (filters != null) {
      if (filters is! Map<String, Object?>) {
        return _fail('search.filters 不合法');
      }
      const Set<String> filterAllowed = <String>{
        'types',
        'tags',
        'todo_status',
        'todo_priority',
      };
      if (!_onlyAllowed(filters, filterAllowed)) {
        return _fail('search.filters 含非法字段');
      }
    }

    return RouterValidationResult.ok;
  }

  RouterValidationResult _validateRefreshBookmarkTitle(
    Map<String, Object?> payload,
  ) {
    if (!_onlyAllowed(payload, const <String>{'bookmark_id'})) {
      return _fail('refresh_bookmark_title payload 含非法字段');
    }
    final String? id = payload['bookmark_id'] as String?;
    if (!_stringLen(id, 8, 80)) {
      return _fail('refresh_bookmark_title.bookmark_id 不合法');
    }
    return RouterValidationResult.ok;
  }

  RouterValidationResult _validateStartFocusTimer(
    Map<String, Object?> payload,
  ) {
    if (!_onlyAllowed(payload, const <String>{
      'mode',
      'focus_minutes',
      'ratio',
    })) {
      return _fail('start_focus_timer payload 含非法字段');
    }
    final String? mode = payload['mode'] as String?;
    final int? focusMinutes = payload['focus_minutes'] as int?;
    final String? ratio = payload['ratio'] as String?;

    if (mode != null &&
        !const <String>{'countdown', 'countup'}.contains(mode)) {
      return _fail('start_focus_timer.mode 不合法');
    }
    if (focusMinutes != null && (focusMinutes < 1 || focusMinutes > 300)) {
      return _fail('start_focus_timer.focus_minutes 不合法');
    }
    if (ratio != null && ratio != '5:1') {
      return _fail('start_focus_timer.ratio 不合法');
    }

    return RouterValidationResult.ok;
  }

  RouterValidationResult _validateMaintenance(Map<String, Object?> payload) {
    if (!_onlyAllowed(payload, const <String>{'task'})) {
      return _fail('maintenance payload 含非法字段');
    }
    final String? task = payload['task'] as String?;
    if (!const <String>{
      'vacuum',
      'rebuild_fts',
      'purge_deleted',
      'purge_orphan_tags',
      'purge_note_versions_keep_latest',
    }.contains(task)) {
      return _fail('maintenance.task 不合法');
    }

    return RouterValidationResult.ok;
  }

  bool _stringLen(String? value, int min, int max) {
    if (value == null) {
      return false;
    }
    return value.length >= min && value.length <= max;
  }

  bool _tags(Object? value, int maxItems) {
    if (value is! List<Object?>) {
      return false;
    }
    if (value.length > maxItems) {
      return false;
    }
    for (final Object? tag in value) {
      if (tag is! String || tag.isEmpty || tag.length > 40) {
        return false;
      }
    }
    return true;
  }

  bool _remindAt(Object value) {
    if (value is int) {
      return value >= 0;
    }
    if (value is String) {
      return value.length >= 5 && value.length <= 40;
    }
    return false;
  }

  bool _onlyAllowed(Map<String, Object?> payload, Set<String> allowed) {
    for (final String key in payload.keys) {
      if (!allowed.contains(key)) {
        return false;
      }
    }
    return true;
  }

  RouterValidationResult _fail(String error) {
    return RouterValidationResult(isValid: false, error: error);
  }
}
