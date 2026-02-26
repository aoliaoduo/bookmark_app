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
      return _fail('root must be a JSON object');
    }

    final Set<String> keys = input.keys.toSet();
    const Set<String> required = <String>{'action', 'confidence', 'payload'};
    if (!keys.containsAll(required)) {
      return _fail('missing required fields: action/confidence/payload');
    }
    if (keys.length != 3) {
      return _fail('only action/confidence/payload are allowed');
    }

    final String? action = input['action'] as String?;
    final num? confidence = input['confidence'] as num?;
    final Object? payload = input['payload'];

    if (action == null || !_actions.contains(action)) {
      return _fail('action is invalid');
    }
    if (confidence == null || confidence < 0 || confidence > 1) {
      return _fail('confidence is invalid');
    }
    if (payload is! Map<String, Object?>) {
      return _fail('payload must be an object');
    }

    return switch (action) {
      'create_todo' => _validateCreateTodo(payload),
      'create_note' => _validateCreateNote(payload),
      'create_bookmark' => _validateCreateBookmark(payload),
      'search' => _validateSearch(payload),
      'refresh_bookmark_title' => _validateRefreshBookmarkTitle(payload),
      'start_focus_timer' => _validateStartFocusTimer(payload),
      'maintenance' => _validateMaintenance(payload),
      _ => _fail('action is not supported'),
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
      return _fail('create_todo payload has invalid fields');
    }

    final String? title = payload['title'] as String?;
    final String? priority = payload['priority'] as String?;
    final Object? tags = payload['tags'];

    if (!_stringLen(title, 1, 200)) {
      return _fail('create_todo.title is invalid');
    }
    if (!const <String>{'high', 'medium', 'low'}.contains(priority)) {
      return _fail('create_todo.priority is invalid');
    }
    if (!_tags(tags, 20)) {
      return _fail('create_todo.tags is invalid');
    }

    final Object? remindAt = payload['remind_at'];
    if (remindAt != null && !_remindAt(remindAt)) {
      return _fail('create_todo.remind_at must be epoch_ms number');
    }

    return RouterValidationResult.ok;
  }

  RouterValidationResult _validateCreateNote(Map<String, Object?> payload) {
    const Set<String> allowed = <String>{'title', 'tags', 'organized_md'};
    if (!_onlyAllowed(payload, allowed)) {
      return _fail('create_note payload has invalid fields');
    }

    final String? title = payload['title'] as String?;
    final Object? tags = payload['tags'];
    final String? organizedMd = payload['organized_md'] as String?;

    if (!_stringLen(title, 1, 200)) {
      return _fail('create_note.title is invalid');
    }
    if (!_tags(tags, 30)) {
      return _fail('create_note.tags is invalid');
    }
    if (!_stringLen(organizedMd, 1, 1000000)) {
      return _fail('create_note.organized_md is invalid');
    }

    return RouterValidationResult.ok;
  }

  RouterValidationResult _validateCreateBookmark(Map<String, Object?> payload) {
    if (!_onlyAllowed(payload, const <String>{'url'})) {
      return _fail('create_bookmark payload has invalid fields');
    }
    final String? url = payload['url'] as String?;
    if (!_stringLen(url, 8, 2000) || !url!.startsWith('https://')) {
      return _fail('create_bookmark.url must be full https url');
    }
    return RouterValidationResult.ok;
  }

  RouterValidationResult _validateSearch(Map<String, Object?> payload) {
    const Set<String> allowed = <String>{'query', 'mode', 'filters'};
    if (!_onlyAllowed(payload, allowed)) {
      return _fail('search payload has invalid fields');
    }

    final String? query = payload['query'] as String?;
    if (!_stringLen(query, 1, 500)) {
      return _fail('search.query is invalid');
    }

    final String? mode = payload['mode'] as String?;
    if (mode != null && !const <String>{'normal', 'deep'}.contains(mode)) {
      return _fail('search.mode is invalid');
    }

    final Object? filters = payload['filters'];
    if (filters != null) {
      if (filters is! Map<String, Object?>) {
        return _fail('search.filters is invalid');
      }
      const Set<String> filterAllowed = <String>{
        'types',
        'tags',
        'todo_status',
        'todo_priority',
      };
      if (!_onlyAllowed(filters, filterAllowed)) {
        return _fail('search.filters has invalid fields');
      }
    }

    return RouterValidationResult.ok;
  }

  RouterValidationResult _validateRefreshBookmarkTitle(
    Map<String, Object?> payload,
  ) {
    if (!_onlyAllowed(payload, const <String>{'bookmark_id'})) {
      return _fail('refresh_bookmark_title payload has invalid fields');
    }
    final String? id = payload['bookmark_id'] as String?;
    if (!_stringLen(id, 8, 80)) {
      return _fail('refresh_bookmark_title.bookmark_id is invalid');
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
      return _fail('start_focus_timer payload has invalid fields');
    }
    final String? mode = payload['mode'] as String?;
    final int? focusMinutes = payload['focus_minutes'] as int?;
    final String? ratio = payload['ratio'] as String?;

    if (mode != null &&
        !const <String>{'countdown', 'countup'}.contains(mode)) {
      return _fail('start_focus_timer.mode is invalid');
    }
    if (focusMinutes != null && (focusMinutes < 1 || focusMinutes > 300)) {
      return _fail('start_focus_timer.focus_minutes is invalid');
    }
    if (ratio != null && ratio != '5:1') {
      return _fail('start_focus_timer.ratio is invalid');
    }

    return RouterValidationResult.ok;
  }

  RouterValidationResult _validateMaintenance(Map<String, Object?> payload) {
    if (!_onlyAllowed(payload, const <String>{'task'})) {
      return _fail('maintenance payload has invalid fields');
    }
    final String? task = payload['task'] as String?;
    if (!const <String>{
      'vacuum',
      'rebuild_fts',
      'purge_deleted',
      'purge_orphan_tags',
      'purge_note_versions_keep_latest',
    }.contains(task)) {
      return _fail('maintenance.task is invalid');
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
    if (value is num) {
      return value.toInt() >= 0;
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
