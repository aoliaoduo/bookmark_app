const String kTitleFetchFailureNotePrefix = 'TITLE_FETCH_FAILURE:';

String buildTitleFetchFailureNote(String message) {
  final String normalized = message.trim();
  if (normalized.isEmpty) {
    return '$kTitleFetchFailureNotePrefix 无法访问目标链接';
  }
  return '$kTitleFetchFailureNotePrefix $normalized';
}

String? parseTitleFetchFailureNote(String? note) {
  if (note == null) {
    return null;
  }
  final String normalized = note.trim();
  if (!normalized.startsWith(kTitleFetchFailureNotePrefix)) {
    return null;
  }
  final String message =
      normalized.substring(kTitleFetchFailureNotePrefix.length).trim();
  return message.isEmpty ? '无法访问目标链接' : message;
}
